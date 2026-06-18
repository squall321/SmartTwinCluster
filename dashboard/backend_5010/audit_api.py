"""
감사 로그 조회 API — GET /api/audit

변경계 작업 기록(audit_log)을 관리자가 조회. username/action/기간 필터 + 페이지네이션.
감사 조회는 관리자만(@permission_required('admin')).
"""
from flask import Blueprint, request, jsonify
from middleware.jwt_middleware import jwt_required, permission_required
from audit_log import _connect, ensure_audit_table

audit_bp = Blueprint('audit', __name__, url_prefix='/api/audit')


@audit_bp.route('', methods=['GET'])
@jwt_required
@permission_required('admin')
def list_audit():
    """감사 로그 조회.

    Query: username, action(prefix 매칭, 예 'node.'), since(ISO), until(ISO),
           limit(기본 100, 최대 1000), offset.
    """
    try:
        ensure_audit_table()  # 최초 호출 시에도 안전(멱등)

        username = request.args.get('username')
        action = request.args.get('action')
        since = request.args.get('since')
        until = request.args.get('until')
        try:
            limit = min(int(request.args.get('limit', 100)), 1000)
        except (TypeError, ValueError):
            limit = 100
        try:
            offset = max(int(request.args.get('offset', 0)), 0)
        except (TypeError, ValueError):
            offset = 0

        where = []
        params = []
        if username:
            where.append("username = ?")
            params.append(username)
        if action:
            where.append("action LIKE ?")
            params.append(action + '%')
        if since:
            where.append("timestamp >= ?")
            params.append(since)
        if until:
            where.append("timestamp <= ?")
            params.append(until)
        where_sql = ("WHERE " + " AND ".join(where)) if where else ""

        conn = _connect()
        total = conn.execute(f"SELECT COUNT(*) AS c FROM audit_log {where_sql}", params).fetchone()['c']
        rows = conn.execute(
            f"SELECT * FROM audit_log {where_sql} ORDER BY id DESC LIMIT ? OFFSET ?",
            params + [limit, offset],
        ).fetchall()
        conn.close()

        return jsonify({
            'success': True,
            'total': total,
            'limit': limit,
            'offset': offset,
            'entries': [dict(r) for r in rows],
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
