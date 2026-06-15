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

from flask import Blueprint, jsonify

from slurm_commands import (
    get_sdiag,
    get_sshare,
    get_sprio,
    get_sstat,
    get_scontrol,
)

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
