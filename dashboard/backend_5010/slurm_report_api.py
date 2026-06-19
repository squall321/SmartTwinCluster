"""
Slurm Report API (read-only)
sreport 기반 사용량 리포트(계정별/사용자별) 조회 전용 Blueprint.

모든 Slurm 명령은 slurm_commands 의 절대경로 래퍼(get_sreport)를 사용한다
(systemd/gunicorn 의 제한된 PATH 에서 bare 이름은 FileNotFoundError 유발).
래퍼는 subprocess.CompletedProcess(result.stdout / result.stderr / result.returncode)를 반환한다.

읽기전용이므로 변경(mutation)/audit/dry_run 은 없다.

응답 규약:
    성공  -> jsonify({'success': True,  'data': ...}), 200
    실패  -> jsonify({'success': False, 'error': ..., 'raw': ...}), 500
파싱에 실패해도 raw stdout 을 함께 반환한다.
"""

import os
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request

from middleware.jwt_middleware import jwt_required, permission_required

from slurm_commands import get_sreport

# MOCK_MODE: 실제 Slurm 명령 미실행(데모/테스트). slurm_admin_api.py 와 동일 규약.
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# url_prefix 는 /api/slurm. slurm_admin_bp(/api/slurm/...) 와 경로가 겹치지 않도록
# reports/usage 만 사용.
slurm_report_bp = Blueprint('slurm_report', __name__, url_prefix='/api/slurm')


# ============================================
# Helpers
# ============================================

def _maybe_int(value: str):
    """'Used' 컬럼은 분 단위 정수일 수 있음. 가능하면 int 변환, 실패하면 문자열 유지."""
    s = (value or '').strip()
    try:
        return int(s)
    except (TypeError, ValueError):
        return s


def _valid_date(value: str) -> bool:
    """YYYY-MM-DD 형식 간단 검증."""
    if not isinstance(value, str):
        return False
    try:
        datetime.strptime(value.strip(), '%Y-%m-%d')
        return True
    except ValueError:
        return False


def _mock_rows(by: str):
    """MOCK_MODE 샘플 데이터. by=account -> {account,login,used}, by=user -> {login,used}."""
    if by == 'user':
        return [
            {'login': 'alice', 'used': 12500},
            {'login': 'bob', 'used': 8300},
            {'login': 'carol', 'used': 4200},
        ]
    # account (기본)
    return [
        {'account': 'research', 'login': 'alice', 'used': 12500},
        {'account': 'research', 'login': 'bob', 'used': 8300},
        {'account': 'engineering', 'login': 'carol', 'used': 4200},
    ]


# ============================================
# GET /api/slurm/reports/usage  -> sreport 사용량(계정별/사용자별)
#   ?start=YYYY-MM-DD&end=YYYY-MM-DD&by=account|user
#   start/end 미지정/형식오류 시 기본 최근 30일.
#   by 미지정/잘못된 값 시 'account' 로 폴백.
# ============================================
@slurm_report_bp.route('/reports/usage', methods=['GET'])
@jwt_required
@permission_required('admin')
def slurm_reports_usage():
    """sreport 사용량 리포트.

    by=account: cluster AccountUtilizationByUser (format=Account,Login,Used)
    by=user:    user TopUsage             (format=Login,Used)
    '-nP': 헤더 없음(-n) + --parsable(-P, '|' 구분). 행을 dict 리스트로 파싱한다.
    """
    try:
        # by: account(기본) / user. 그 외 값은 account 로 폴백.
        by = (request.args.get('by') or 'account').strip().lower()
        if by != 'user':
            by = 'account'

        # 날짜: 미지정/형식오류면 기본 최근 30일.
        end = request.args.get('end')
        start = request.args.get('start')
        if not _valid_date(end):
            end = datetime.now().strftime('%Y-%m-%d')
        if not _valid_date(start):
            start = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')

        # MOCK_MODE: 실제 sreport 미실행, 샘플 데이터 반환.
        if MOCK_MODE:
            return jsonify({
                'success': True,
                'data': {
                    'by': by,
                    'start': start,
                    'end': end,
                    'rows': _mock_rows(by),
                    'raw': '',
                    'mode': 'mock',
                },
            }), 200

        if by == 'user':
            result = get_sreport(
                '-nP', 'user', 'TopUsage',
                f'start={start}', f'end={end}',
                'format=Login,Used',
                check=False,
            )
        else:  # account
            result = get_sreport(
                '-nP', 'cluster', 'AccountUtilizationByUser',
                f'start={start}', f'end={end}',
                'format=Account,Login,Used',
                check=False,
            )

        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sreport failed').strip(),
                'raw': raw,
            }), 500

        # '-nP' 출력은 헤더 없는 '|' 구분 행들. format 순서대로 컬럼을 매핑한다.
        rows = []
        for line in raw.splitlines():
            if not line.strip():
                continue
            cols = line.split('|')
            if by == 'user':
                # format=Login,Used
                rows.append({
                    'login': cols[0].strip() if len(cols) > 0 else '',
                    'used': _maybe_int(cols[1]) if len(cols) > 1 else '',
                })
            else:
                # format=Account,Login,Used
                rows.append({
                    'account': cols[0].strip() if len(cols) > 0 else '',
                    'login': cols[1].strip() if len(cols) > 1 else '',
                    'used': _maybe_int(cols[2]) if len(cols) > 2 else '',
                })

        return jsonify({
            'success': True,
            'data': {
                'by': by,
                'start': start,
                'end': end,
                'rows': rows,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e), 'raw': ''}), 500
