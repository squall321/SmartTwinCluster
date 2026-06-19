"""
Slurm Reservation API
scontrol 기반 Slurm 예약(Reservation) 관리 Blueprint.

읽기(GET)는 MOCK_MODE 와 무관하게 항상 실제 scontrol 을 실행한다.
변경계(POST/DELETE)는 slurm_admin_api.py 의 _run_scontrol_mutation 안전패턴을 그대로 모방:
    dry_run(기본 True)  -> 실제 실행 없이 생성될 scontrol 명령 문자열만 반환
    MOCK_MODE           -> 실행 흉내(mock), 실제 변경 없음
    실제 성공           -> audit 기록(log_admin_action)

모든 Slurm 명령은 slurm_commands 의 절대경로 래퍼 get_scontrol 을 사용한다
(systemd/gunicorn 의 제한된 PATH 에서 bare 이름은 FileNotFoundError 유발).
get_scontrol 는 subprocess.CompletedProcess(result.stdout / result.stderr / result.returncode)를 반환한다.

응답 규약:
    성공  -> jsonify({'success': True,  'data': ...}), 200
    실패  -> jsonify({'success': False, 'error': ...}), 500 (필수 누락은 400)
파싱에 실패해도 raw stdout 을 함께 반환한다.
"""

import os

from flask import Blueprint, jsonify, request

from middleware.jwt_middleware import jwt_required, permission_required
from audit_log import log_admin_action

from slurm_commands import get_scontrol

# MOCK_MODE: 실제 Slurm 변경 미실행(데모/테스트). slurm_admin_api.py 와 동일 규약.
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# url_prefix 는 /api/slurm. 경로는 /reservations 만 사용하여 기존 Blueprint 와 겹치지 않게 한다.
slurm_reservation_bp = Blueprint('slurm_reservation', __name__, url_prefix='/api/slurm')


# ============================================
# Helpers
# ============================================

def _parse_kv_line(line: str) -> dict:
    """'Key=Value Key=Value ...' 한 줄(scontrol -o 포맷)을 dict 로.

    값에 '=' 가 들어가는 일부 필드를 고려해 첫 '=' 만 split.
    (slurm_admin_api.py 의 동일 로직을 복사 — import 의존 회피.)
    """
    record = {}
    for token in line.split():
        if '=' in token:
            key, _, value = token.partition('=')
            record[key] = value
    return record


# 예약마다 우선적으로 노출할 키 목록(프론트 계약). 파싱은 전체 Key=Value 를 담되
# 프론트는 아래 키를 안정적으로 기대할 수 있다(scontrol 미출력 시 키 자체가 없을 수 있음).
_RESERVATION_KEYS = [
    'ReservationName', 'StartTime', 'EndTime', 'Duration',
    'Nodes', 'NodeCnt', 'Users', 'Accounts',
    'PartitionName', 'State', 'Flags',
]


def _reservation_command_str(*args) -> str:
    """생성될 scontrol 명령을 사람이 읽을 수 있는 문자열로 (dry_run 응답/감사용)."""
    return 'scontrol ' + ' '.join(str(a) for a in args)


# ============================================
# GET /api/slurm/reservations  -> scontrol -o show reservation
#   읽기 전용. MOCK_MODE 무시하고 실제 실행.
# ============================================
@slurm_reservation_bp.route('/reservations', methods=['GET'])
@jwt_required
@permission_required('admin')
def list_reservations():
    """scontrol -o show reservation (한 줄 포맷 Key=Value 파싱).

    예약이 없으면 'No reservations in the system' 한 줄이 나오며 빈 배열을 반환한다.
    """
    try:
        result = get_scontrol('-o', 'show', 'reservation', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'scontrol show reservation failed').strip(),
                'raw': raw,
            }), 500

        reservations = []
        for line in raw.splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            # 'No reservations in the system' 등 Key=Value 가 아닌 라인은 건너뛴다.
            if 'No reservations' in stripped:
                continue
            record = _parse_kv_line(line)
            if 'ReservationName' in record:
                reservations.append(record)

        return jsonify({
            'success': True,
            'data': {
                'reservations': reservations,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/reservations  -> scontrol create reservation ...
#   변경계. dry_run(기본 True) -> command, MOCK -> mock, 실제성공 -> audit.
# ============================================
@slurm_reservation_bp.route('/reservations', methods=['POST'])
@jwt_required
@permission_required('admin')
def create_reservation():
    """scontrol create reservation (예약 생성). dry_run 기본 True.

    Body:
        reservation_name?  예약명(미지정 시 Slurm 자동 명명)
        starttime          필수. 예: now / 2026-06-20T09:00:00
        duration?          예: 120 또는 2:00:00      (duration 또는 endtime 중 하나 필수)
        endtime?           예: 2026-06-20T11:00:00
        users?             콤마 문자열                (users 또는 accounts 중 하나 필수)
        accounts?          콤마 문자열
        nodes?             예: cn[01-04]              (nodes/partition/flags=MAINT 중 하나 권장)
        partition?         파티션명
        flags?             예: MAINT,IGNORE_JOBS
        dry_run=true       실제 실행 없이 명령 문자열만 반환
    """
    try:
        body = request.get_json(silent=True) or {}

        reservation_name = body.get('reservation_name')
        starttime = body.get('starttime')
        duration = body.get('duration')
        endtime = body.get('endtime')
        users = body.get('users')
        accounts = body.get('accounts')
        nodes = body.get('nodes')
        partition = body.get('partition')
        flags = body.get('flags')

        # 최소 검증.
        if not starttime:
            return jsonify({'success': False, 'error': "'starttime' is required"}), 400
        if not duration and not endtime:
            return jsonify({
                'success': False,
                'error': "one of 'duration' or 'endtime' is required",
            }), 400
        if not users and not accounts:
            return jsonify({
                'success': False,
                'error': "one of 'users' or 'accounts' is required",
            }), 400
        # nodes/partition/flags=MAINT 중 하나는 권장이나, 없어도 경고 없이 진행.

        # 명령 토큰 조립: scontrol create reservation Key=Value ...
        tokens = ['create', 'reservation']
        if reservation_name:
            tokens.append(f'ReservationName={reservation_name}')
        tokens.append(f'starttime={starttime}')
        # duration 우선, 없으면 endtime.
        if duration:
            tokens.append(f'duration={duration}')
        else:
            tokens.append(f'endtime={endtime}')
        # user 우선, 없으면 account.
        if users:
            tokens.append(f'user={users}')
        else:
            tokens.append(f'account={accounts}')
        # nodes 우선, 없으면 partition (둘 다 없으면 생략).
        if nodes:
            tokens.append(f'nodes={nodes}')
        elif partition:
            tokens.append(f'partition={partition}')
        if flags:
            tokens.append(f'flags={flags}')

        command = _reservation_command_str(*tokens)
        dry_run = bool((request.get_json(silent=True) or {}).get('dry_run', True))

        if dry_run:
            return jsonify({
                'success': True,
                'dry_run': True,
                'command': command,
            }), 200

        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'command': command,
                'message': f"Reservation {reservation_name or '(auto)'} created (Mock)",
            }), 200

        result = get_scontrol(*tokens, check=False)
        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'scontrol create reservation failed').strip(),
                'command': command,
            }), 500

        # 감사 기록: 실제 변경 성공만(dry_run/mock 은 위에서 반환되어 여기 안 옴).
        log_admin_action(
            'reservation.create',
            reservation_name or '(auto)',
            detail={'command': command},
        )

        return jsonify({
            'success': True,
            'mode': 'production',
            'command': command,
            'message': f"Reservation {reservation_name or '(auto)'} created",
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# DELETE /api/slurm/reservations/<name>  -> scontrol delete ReservationName=<name>
#   변경계. dry_run(기본 True) -> command, MOCK -> mock, 실제성공 -> audit.
# ============================================
@slurm_reservation_bp.route('/reservations/<name>', methods=['DELETE'])
@jwt_required
@permission_required('admin')
def delete_reservation(name):
    """scontrol delete ReservationName=<name> (예약 삭제). dry_run 기본 True.

    Body:
        dry_run=true  실제 실행 없이 명령 문자열만 반환
    """
    try:
        tokens = ['delete', f'ReservationName={name}']
        command = _reservation_command_str(*tokens)
        dry_run = bool((request.get_json(silent=True) or {}).get('dry_run', True))

        if dry_run:
            return jsonify({
                'success': True,
                'dry_run': True,
                'command': command,
            }), 200

        if MOCK_MODE:
            return jsonify({
                'success': True,
                'mode': 'mock',
                'command': command,
                'message': f'Reservation {name} deleted (Mock)',
            }), 200

        result = get_scontrol(*tokens, check=False)
        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'scontrol delete reservation failed').strip(),
                'command': command,
            }), 500

        # 감사 기록: 실제 변경 성공만.
        log_admin_action('reservation.delete', name, detail={'command': command})

        return jsonify({
            'success': True,
            'mode': 'production',
            'command': command,
            'message': f'Reservation {name} deleted',
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
