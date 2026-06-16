"""
Slurm Admin API (read-only)
스케줄러 진단/공정공유/우선순위/실행중 잡 리소스/컨트롤러/파티션 조회 전용 Blueprint.

모든 Slurm 명령은 slurm_commands 의 절대경로 래퍼(get_*)를 사용한다
(systemd/gunicorn 의 제한된 PATH 에서 bare 이름은 FileNotFoundError 유발).
각 래퍼는 subprocess.CompletedProcess(result.stdout / result.returncode)를 반환한다.

응답 규약:
    성공  -> jsonify({'success': True,  'data': ...}), 200
    실패  -> jsonify({'success': False, 'error': ...}), 500
파싱에 실패해도 raw stdout 을 함께 반환한다.
"""

import os

from flask import Blueprint, jsonify, request

from middleware.jwt_middleware import jwt_required, permission_required

from slurm_commands import (
    get_sdiag,
    get_sshare,
    get_sprio,
    get_sstat,
    get_scontrol,
)

# MOCK_MODE: 실제 Slurm 명령 미실행(데모/테스트). app.py / node_management_api.py 와 동일 규약.
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# url_prefix 는 /api/slurm. 기존 app.py 의 @app.route('/api/slurm/...') 및
# lsdyna_submit_bp(/api/slurm/submit-lsdyna-jobs) 와 경로가 겹치지 않도록
# diag / fairshare / jobs/priority / jobs/<id>/stat / controller/ping / partitions 만 사용.
slurm_admin_bp = Blueprint('slurm_admin', __name__, url_prefix='/api/slurm')


# ============================================
# Helpers
# ============================================

def _parse_kv_line(line: str) -> dict:
    """'Key=Value Key=Value ...' 한 줄(scontrol -o 포맷)을 dict 로.

    값에 '=' 가 들어가는 일부 필드를 고려해 첫 '=' 만 split.
    """
    record = {}
    for token in line.split():
        if '=' in token:
            key, _, value = token.partition('=')
            record[key] = value
    return record


# ============================================
# GET /api/slurm/diag  -> sdiag (스케줄러 진단)
# ============================================
@slurm_admin_bp.route('/diag', methods=['GET'])
def slurm_diag():
    """sdiag 스케줄러 진단. raw stdout + 핵심 파싱(key: value)."""
    try:
        result = get_sdiag(check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sdiag failed').strip(),
                'raw': raw,
            }), 500

        # sdiag 출력은 'Key: Value' 형태의 라인들. 들여쓰기/콜론 기반 평면 파싱.
        parsed = {}
        for line in raw.splitlines():
            if ':' not in line:
                continue
            key, _, value = line.partition(':')
            key = key.strip()
            value = value.strip()
            if key and value:
                parsed[key] = value

        return jsonify({
            'success': True,
            'data': {
                'parsed': parsed,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/fairshare  -> sshare -P -a
# ============================================
@slurm_admin_bp.route('/fairshare', methods=['GET'])
def slurm_fairshare():
    """sshare -P -a (--parsable2). 헤더 기반 dict 리스트로 파싱."""
    try:
        result = get_sshare('-P', '-a', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sshare failed').strip(),
                'raw': raw,
            }), 500

        lines = [ln for ln in raw.splitlines() if ln.strip()]
        rows = []
        if lines:
            headers = [h.strip() for h in lines[0].split('|')]
            for line in lines[1:]:
                cols = line.split('|')
                rows.append({
                    headers[i] if i < len(headers) else f'col{i}': cols[i].strip()
                    for i in range(len(cols))
                })

        return jsonify({
            'success': True,
            'data': {
                'fairshare': rows,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/jobs/priority  -> sprio -l
# ============================================
@slurm_admin_bp.route('/jobs/priority', methods=['GET'])
def slurm_jobs_priority():
    """sprio -l (우선순위 분해). 공백 구분 표 형태를 헤더 기반 파싱."""
    try:
        result = get_sprio('-l', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sprio failed').strip(),
                'raw': raw,
            }), 500

        lines = [ln for ln in raw.splitlines() if ln.strip()]
        rows = []
        if lines:
            headers = lines[0].split()
            for line in lines[1:]:
                cols = line.split()
                rows.append({
                    headers[i] if i < len(headers) else f'col{i}': cols[i]
                    for i in range(len(cols))
                })

        return jsonify({
            'success': True,
            'data': {
                'priorities': rows,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/jobs/<job_id>/stat  -> sstat -j <id> -P -a
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/stat', methods=['GET'])
def slurm_job_stat(job_id):
    """sstat -j <id> -P -a (실행중 잡 리소스). --parsable2 헤더 기반 파싱."""
    try:
        result = get_sstat('-j', str(job_id), '-P', '-a', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sstat failed').strip(),
                'raw': raw,
            }), 500

        lines = [ln for ln in raw.splitlines() if ln.strip()]
        rows = []
        if lines:
            headers = [h.strip() for h in lines[0].split('|')]
            for line in lines[1:]:
                cols = line.split('|')
                rows.append({
                    headers[i] if i < len(headers) else f'col{i}': cols[i].strip()
                    for i in range(len(cols))
                })

        return jsonify({
            'success': True,
            'data': {
                'job_id': str(job_id),
                'stats': rows,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/controller/ping  -> scontrol ping
# ============================================
@slurm_admin_bp.route('/controller/ping', methods=['GET'])
def slurm_controller_ping():
    """scontrol ping (컨트롤러 응답성)."""
    try:
        result = get_scontrol('ping', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'scontrol ping failed').strip(),
                'raw': raw,
            }), 500

        # 'Slurmctld(primary) at host is UP/DOWN' 형태. 라인 그대로 + UP 여부 요약.
        controllers = []
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            controllers.append({
                'line': line,
                'up': 'UP' in line.upper(),
            })

        return jsonify({
            'success': True,
            'data': {
                'controllers': controllers,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/partitions  -> scontrol show partition -o
# ============================================
@slurm_admin_bp.route('/partitions', methods=['GET'])
def slurm_partitions():
    """scontrol show partition -o (한 줄 포맷 Key=Value 파싱)."""
    try:
        result = get_scontrol('show', 'partition', '-o', check=False)
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'scontrol show partition failed').strip(),
                'raw': raw,
            }), 500

        partitions = []
        for line in raw.splitlines():
            if not line.strip():
                continue
            record = _parse_kv_line(line)
            if record:
                partitions.append(record)

        return jsonify({
            'success': True,
            'data': {
                'partitions': partitions,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# Mutating section (변경계)
#
# 모든 변경계 라우트는 인증 필수:
#   @jwt_required + @permission_required('dashboard')
# (app.py 의 hold_job/release_job 와 동일 패턴 — MOCK 분기 + get_scontrol 래퍼)
#
# Slurm 호출은 slurm_commands 의 get_scontrol(절대경로, CompletedProcess) 사용.
# 위험 입력(상태값/액션/필드)은 화이트리스트로 제약하고, update Key=Val 의 Val 은
# 타입검증(정수/시간포맷)으로 안전하게 만든다. job_id 는 URL 경로 정수.
#
# dry_run: body 의 dry_run=true 면 실제 실행 대신 생성될 scontrol 명령 문자열을 반환.
# ============================================

# PATCH /jobs/<id> 에서 허용하는 scontrol update job= 필드 화이트리스트.
# 값(value)은 validator 로 검증한다. 그 외 키는 무시되고, 유효 필드가 하나도 없으면 400.
_UPDATE_FIELD_VALIDATORS = {
    'TimeLimit': '_validate_timelimit',
    'Nice': '_validate_int',
    'Priority': '_validate_uint',
    'Partition': '_validate_name',
    'QOS': '_validate_name',
}


def _validate_int(value):
    """부호 있는 정수. (int, None) 반환, 실패 시 (None, error)."""
    try:
        return int(str(value).strip()), None
    except (TypeError, ValueError):
        return None, 'must be an integer'


def _validate_uint(value):
    """0 이상 정수."""
    n, err = _validate_int(value)
    if err:
        return None, err
    if n < 0:
        return None, 'must be a non-negative integer'
    return n, None


def _validate_timelimit(value):
    """scontrol TimeLimit 포맷만 허용: minutes | mm:ss | hh:mm:ss | d-hh | d-hh:mm | d-hh:mm:ss.

    임의 플래그 주입 방지를 위해 [0-9:-] 문자만 허용.
    """
    s = str(value).strip()
    if not s or any(c not in '0123456789:-' for c in s):
        return None, 'invalid TimeLimit format'
    return s, None


def _validate_name(value):
    """파티션/QOS 이름. 영숫자/_/-/, 만 허용(쉼표=목록)."""
    s = str(value).strip()
    if not s or any(not (c.isalnum() or c in '_-,') for c in s):
        return None, 'invalid name'
    return s, None


# 디스패치: validator 이름 -> 함수
_VALIDATORS = {
    '_validate_int': _validate_int,
    '_validate_uint': _validate_uint,
    '_validate_timelimit': _validate_timelimit,
    '_validate_name': _validate_name,
}


def _scontrol_str(*args) -> str:
    """생성될 scontrol 명령을 사람이 읽을 수 있는 문자열로 (dry_run 응답용)."""
    return 'scontrol ' + ' '.join(str(a) for a in args)


def _run_scontrol_mutation(args, dry_run, success_message):
    """변경계 scontrol 호출 공통 처리.

    args: get_scontrol 에 전달할 위치인자 튜플 (예: ('requeue', '123')).
    dry_run True 면 실제 실행 없이 명령 문자열 반환.
    성공 -> (payload, 200), 실패 -> (payload, status).
    """
    command = _scontrol_str(*args)

    if dry_run:
        return {
            'success': True,
            'dry_run': True,
            'command': command,
        }, 200

    if MOCK_MODE:
        return {
            'success': True,
            'mode': 'mock',
            'command': command,
            'message': f'{success_message} (Mock)',
        }, 200

    result = get_scontrol(*args, check=False)
    if result.returncode != 0:
        return {
            'success': False,
            'error': (result.stderr or 'scontrol failed').strip(),
            'command': command,
        }, 500

    return {
        'success': True,
        'mode': 'production',
        'command': command,
        'message': success_message,
    }, 200


# ============================================
# POST /api/slurm/jobs/<job_id>/requeue  -> scontrol requeue <id>
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/requeue', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_job_requeue(job_id):
    """scontrol requeue <id> (잡 재큐). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}
        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('requeue', str(job_id)),
            dry_run,
            f'Job {job_id} requeued',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/jobs/<job_id>/requeuehold  -> scontrol requeuehold <id>
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/requeuehold', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_job_requeuehold(job_id):
    """scontrol requeuehold <id> (재큐 후 hold). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}
        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('requeuehold', str(job_id)),
            dry_run,
            f'Job {job_id} requeued and held',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# PATCH /api/slurm/jobs/<job_id>  -> scontrol update job=<id> Key=Val ...
#   허용 필드(화이트리스트): TimeLimit / Nice / Priority / Partition / QOS
#   그 외 키는 무시. 유효 필드 0개면 400.
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>', methods=['PATCH'])
@jwt_required
@permission_required('dashboard')
def slurm_job_update(job_id):
    """scontrol update job=<id> (허용 필드만). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}

        accepted = {}    # Key -> 검증된 값
        ignored = []     # 화이트리스트에 없는 키
        for key, raw_value in body.items():
            if key == 'dry_run':
                continue
            if key not in _UPDATE_FIELD_VALIDATORS:
                ignored.append(key)
                continue
            validator = _VALIDATORS[_UPDATE_FIELD_VALIDATORS[key]]
            value, err = validator(raw_value)
            if err:
                return jsonify({
                    'success': False,
                    'error': f"field '{key}' {err}",
                }), 400
            accepted[key] = value

        if not accepted:
            return jsonify({
                'success': False,
                'error': 'no valid updatable fields provided',
                'allowed_fields': sorted(_UPDATE_FIELD_VALIDATORS.keys()),
                'ignored': ignored,
            }), 400

        dry_run = bool(body.get('dry_run', False))
        # scontrol update job=<id> Key=Val ...
        args = ['update', f'job={job_id}'] + [
            f'{key}={value}' for key, value in accepted.items()
        ]
        payload, status = _run_scontrol_mutation(
            tuple(args),
            dry_run,
            f'Job {job_id} updated',
        )
        if ignored:
            payload['ignored'] = ignored
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/jobs/<job_id>/priority  -> scontrol update job=<id> Priority=N
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/priority', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_job_priority(job_id):
    """scontrol update job=<id> Priority=N (정수 검증). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}
        if 'priority' not in body:
            return jsonify({'success': False, 'error': "'priority' is required"}), 400

        priority, err = _validate_uint(body.get('priority'))
        if err:
            return jsonify({'success': False, 'error': f"'priority' {err}"}), 400

        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('update', f'job={job_id}', f'Priority={priority}'),
            dry_run,
            f'Job {job_id} priority set to {priority}',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/jobs/<job_id>/nice  -> scontrol update job=<id> Nice=N
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/nice', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_job_nice(job_id):
    """scontrol update job=<id> Nice=N (정수 검증). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}
        if 'nice' not in body:
            return jsonify({'success': False, 'error': "'nice' is required"}), 400

        nice, err = _validate_int(body.get('nice'))
        if err:
            return jsonify({'success': False, 'error': f"'nice' {err}"}), 400

        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('update', f'job={job_id}', f'Nice={nice}'),
            dry_run,
            f'Job {job_id} nice set to {nice}',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/jobs/<job_id>/top  -> scontrol top <id>
#   사용자 큐 최상단 이동(비관리자 가능).
# ============================================
@slurm_admin_bp.route('/jobs/<job_id>/top', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_job_top(job_id):
    """scontrol top <id> (사용자 큐 최상단). dry_run 지원."""
    try:
        body = request.get_json(silent=True) or {}
        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('top', str(job_id)),
            dry_run,
            f'Job {job_id} moved to top of queue',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# === Partition mutating ===
# 파티션 상태/속성 변경계 라우트. 위 잡 변경계와 같은 slurm_admin_bp / 공통 헬퍼 재사용.
#
# 보안/규약:
#   - @jwt_required + @permission_required('dashboard') 로 인증(app.py hold_job 패턴).
#   - 실행은 위 _run_scontrol_mutation (dry_run + MOCK_MODE + get_scontrol CompletedProcess).
#   - 위험 입력(상태값/필드)은 enum/화이트리스트로 제약 — 임의 플래그 차단.
#   - 파티션명은 영숫자/_/- 만 허용(정규식).
#
# 상단 import 블록은 동시 수정 충돌 방지를 위해 편집하지 않는다. request/MOCK_MODE/
# jwt_required/permission_required/get_scontrol/_run_scontrol_mutation 는 이미 위에 존재해
# 재사용한다. re 만 이 섹션 내 지역 import.
import re as _re

# scontrol update PartitionName=<name> State=<STATE> 에 허용되는 상태값 화이트리스트.
_PARTITION_STATES = {'UP', 'DOWN', 'DRAIN', 'INACTIVE'}

# PATCH 로 변경 가능한 필드 화이트리스트(scontrol update PartitionName=... Key=Val).
_PARTITION_PATCH_FIELDS = {'Nodes', 'MaxTime', 'Default', 'MaxNodes', 'State'}

# 파티션명: 영숫자 / '_' / '-' 만 허용(쉼표 불가).
_PARTITION_NAME_RE = _re.compile(r'^[A-Za-z0-9_-]+$')


def _valid_partition_name(name) -> bool:
    # fullmatch: '$' 는 문자열 끝의 trailing newline 직전에도 매치되므로
    # 'a\n' 같은 우회를 막기 위해 match 대신 fullmatch 사용.
    return isinstance(name, str) and bool(_PARTITION_NAME_RE.fullmatch(name))


@slurm_admin_bp.route('/partitions/<name>/state', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def slurm_partition_set_state(name):
    """파티션 상태 변경 - JWT 인증 필요.

    body.state ∈ {UP, DOWN, DRAIN, INACTIVE} (enum 강제, 아니면 400).
    scontrol update PartitionName=<name> State=<STATE> (런타임 적용, reconfigure 불필요).
    body.dry_run=true 면 실제 실행 대신 생성될 명령 문자열만 반환.
    """
    try:
        if not _valid_partition_name(name):
            return jsonify({
                'success': False,
                'error': 'invalid partition name (allowed: alphanumeric, _, -)',
            }), 400

        body = request.get_json(silent=True) or {}
        state = body.get('state')
        if not isinstance(state, str) or state.upper() not in _PARTITION_STATES:
            return jsonify({
                'success': False,
                'error': f'state must be one of {sorted(_PARTITION_STATES)}',
            }), 400
        state = state.upper()

        dry_run = bool(body.get('dry_run', False))
        payload, status = _run_scontrol_mutation(
            ('update', f'PartitionName={name}', f'State={state}'),
            dry_run,
            f'Partition {name} state set to {state}',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@slurm_admin_bp.route('/partitions/<name>', methods=['PATCH'])
@jwt_required
@permission_required('dashboard')
def slurm_partition_update(name):
    """파티션 속성 변경 - JWT 인증 필요.

    허용 필드 화이트리스트: {Nodes, MaxTime, Default, MaxNodes, State}.
    화이트리스트 밖 키는 400 (임의 플래그/필드 주입 차단).
    scontrol update PartitionName=<name> Key=Val ...
    body.dry_run=true 면 실제 실행 대신 생성될 명령 문자열만 반환.
    """
    try:
        if not _valid_partition_name(name):
            return jsonify({
                'success': False,
                'error': 'invalid partition name (allowed: alphanumeric, _, -)',
            }), 400

        body = request.get_json(silent=True) or {}
        dry_run = bool(body.get('dry_run', False))

        # dry_run 은 제어 파라미터이므로 변경 필드에서 제외.
        fields = {k: v for k, v in body.items() if k != 'dry_run'}
        if not fields:
            return jsonify({'success': False, 'error': 'no fields to update'}), 400

        invalid = [k for k in fields if k not in _PARTITION_PATCH_FIELDS]
        if invalid:
            return jsonify({
                'success': False,
                'error': (
                    f'unknown field(s): {invalid}. '
                    f'allowed: {sorted(_PARTITION_PATCH_FIELDS)}'
                ),
            }), 400

        # State 필드는 상태 enum 으로 추가 검증.
        if 'State' in fields:
            st = fields['State']
            if not isinstance(st, str) or st.upper() not in _PARTITION_STATES:
                return jsonify({
                    'success': False,
                    'error': f'State must be one of {sorted(_PARTITION_STATES)}',
                }), 400
            fields['State'] = st.upper()

        # Key=Val 토큰 구성. 값에 공백/개행이 들어가면 scontrol 토큰이 깨지므로 거부.
        kv_args = []
        for key in sorted(fields):  # 결정적 순서.
            val = fields[key]
            if isinstance(val, bool):
                val = 'YES' if val else 'NO'
            else:
                val = str(val)
            if not val or any(c.isspace() for c in val):
                return jsonify({
                    'success': False,
                    'error': f'invalid value for {key} (must be non-empty, no whitespace)',
                }), 400
            kv_args.append(f'{key}={val}')

        args = tuple(['update', f'PartitionName={name}'] + kv_args)
        payload, status = _run_scontrol_mutation(
            args,
            dry_run,
            f'Partition {name} updated',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
