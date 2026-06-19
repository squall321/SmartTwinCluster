"""
Slurm Account/Association API
sacctmgr 기반 계정(Account)/연관(Association) 관리 Blueprint.

slurm_admin_api.py 와 동일 규약:
  - 모든 Slurm 명령은 slurm_commands 의 절대경로 래퍼(get_sacctmgr)를 사용한다
    (systemd/gunicorn 의 제한된 PATH 에서 bare 이름은 FileNotFoundError 유발).
    래퍼는 subprocess.CompletedProcess(.stdout / .stderr / .returncode)를 반환한다.
  - 읽기(show)는 use_sudo=False, 쓰기(add/delete)는 기본(use_sudo=True).

응답 규약:
    성공  -> jsonify({'success': True,  'data': ...}), 200
    실패  -> jsonify({'success': False, 'error': ...}), 500
    파싱에 실패해도 raw stdout 을 함께 반환한다.

변경계(쓰기) 안전 패턴(slurm_admin_api._run_scontrol_mutation 모방):
    dry_run(기본 True) -> 실제 실행 없이 생성될 command 문자열만 반환
    MOCK_MODE          -> 실제 실행 없이 mock 반환
    실제 실행 성공     -> log_admin_action 으로 감사 기록
"""

import os

from flask import Blueprint, jsonify, request

from middleware.jwt_middleware import jwt_required, permission_required
from audit_log import log_admin_action

from slurm_commands import get_sacctmgr

# MOCK_MODE: 실제 Slurm 명령 미실행(데모/테스트). app.py / slurm_admin_api.py 와 동일 규약.
# 읽기(show)는 안전하므로 MOCK_MODE 무시하고 실제 실행, 쓰기만 MOCK 분기.
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# url_prefix 는 /api/slurm (slurm_admin_bp 와 동일 prefix). 이름은 'slurm_account' 로 고유.
# 경로(/accounts, /associations)가 slurm_admin 의 경로와 겹치지 않으므로 충돌 없음.
slurm_account_bp = Blueprint('slurm_account', __name__, url_prefix='/api/slurm')


# ============================================
# Helpers
# ============================================

def _run_sacctmgr_mutation(args, dry_run, command, audit_action, audit_target):
    """변경계 sacctmgr 호출 공통 처리(slurm_admin_api._run_scontrol_mutation 모방).

    args: get_sacctmgr 에 전달할 위치인자 튜플(use_sudo 기본 True).
    command: 사람이 읽기 좋은 명령 문자열(dry_run 응답 + audit detail 동일 사용).
    dry_run True 면 실제 실행 없이 command 문자열 반환.
    실제 실행 성공만 log_admin_action 기록.
    성공 -> (payload, 200), 실패 -> (payload, status).
    """
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
        }, 200

    result = get_sacctmgr(*args, check=False)
    if result.returncode != 0:
        return {
            'success': False,
            'error': (result.stderr or 'sacctmgr failed').strip(),
            'command': command,
        }, 500

    # 감사 기록: 실제 변경 성공만(dry_run/mock 은 위에서 이미 반환되어 여기 안 옴)
    log_admin_action(audit_action, audit_target, detail={'command': command})

    return {
        'success': True,
        'mode': 'production',
        'command': command,
    }, 200


# ============================================
# GET /api/slurm/accounts  -> sacctmgr -nP show account
# ============================================
@slurm_account_bp.route('/accounts', methods=['GET'])
@jwt_required
@permission_required('admin')
def slurm_accounts_list():
    """sacctmgr -nP show account format=Account,Descr,Org ('|' 구분 파싱)."""
    try:
        result = get_sacctmgr(
            '-nP', 'show', 'account', 'format=Account,Descr,Org',
            use_sudo=False, check=False,
        )
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sacctmgr show account failed').strip(),
                'raw': raw,
            }), 500

        accounts = []
        for line in raw.splitlines():
            if not line.strip():
                continue
            cols = line.split('|')
            accounts.append({
                'account': cols[0].strip() if len(cols) > 0 else '',
                'description': cols[1].strip() if len(cols) > 1 else '',
                'organization': cols[2].strip() if len(cols) > 2 else '',
            })

        return jsonify({
            'success': True,
            'data': {
                'accounts': accounts,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# GET /api/slurm/associations  -> sacctmgr -nP show assoc
# ============================================
@slurm_account_bp.route('/associations', methods=['GET'])
@jwt_required
@permission_required('admin')
def slurm_associations_list():
    """sacctmgr -nP show assoc format=Account,User,Partition,QOS,DefQOS,GrpTRES ('|' 파싱)."""
    try:
        result = get_sacctmgr(
            '-nP', 'show', 'assoc',
            'format=Account,User,Partition,QOS,DefQOS,GrpTRES',
            use_sudo=False, check=False,
        )
        raw = result.stdout or ''

        if result.returncode != 0:
            return jsonify({
                'success': False,
                'error': (result.stderr or 'sacctmgr show assoc failed').strip(),
                'raw': raw,
            }), 500

        associations = []
        for line in raw.splitlines():
            if not line.strip():
                continue
            cols = line.split('|')
            associations.append({
                'account': cols[0].strip() if len(cols) > 0 else '',
                'user': cols[1].strip() if len(cols) > 1 else '',
                'partition': cols[2].strip() if len(cols) > 2 else '',
                'qos': cols[3].strip() if len(cols) > 3 else '',
                'def_qos': cols[4].strip() if len(cols) > 4 else '',
                'grp_tres': cols[5].strip() if len(cols) > 5 else '',
            })

        return jsonify({
            'success': True,
            'data': {
                'associations': associations,
                'raw': raw,
            },
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/accounts  -> sacctmgr -i add account <account> [Description=] [Organization=]
# ============================================
@slurm_account_bp.route('/accounts', methods=['POST'])
@jwt_required
@permission_required('admin')
def slurm_account_create():
    """sacctmgr -i add account <account>. dry_run 기본 True."""
    try:
        body = request.get_json(silent=True) or {}
        account = (body.get('account') or '').strip()
        if not account:
            return jsonify({'success': False, 'error': "'account' is required"}), 400

        description = (body.get('description') or '').strip()
        organization = (body.get('organization') or '').strip()
        dry_run = bool(body.get('dry_run', True))

        # 명령 인자(토큰) 구성. get_sacctmgr 위치인자와 command 문자열을 동일 토큰으로.
        args = ['-i', 'add', 'account', account]
        if description:
            args.append(f'Description={description}')
        if organization:
            args.append(f'Organization={organization}')
        command = 'sacctmgr ' + ' '.join(args)

        payload, status = _run_sacctmgr_mutation(
            tuple(args), dry_run, command,
            'account.create', account,
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# DELETE /api/slurm/accounts/<account>  -> sacctmgr -i delete account <account>
# ============================================
@slurm_account_bp.route('/accounts/<account>', methods=['DELETE'])
@jwt_required
@permission_required('admin')
def slurm_account_delete(account):
    """sacctmgr -i delete account <account>. dry_run 기본 True."""
    try:
        dry_run = bool((request.get_json(silent=True) or {}).get('dry_run', True))

        args = ['-i', 'delete', 'account', account]
        command = 'sacctmgr ' + ' '.join(args)

        payload, status = _run_sacctmgr_mutation(
            tuple(args), dry_run, command,
            'account.delete', account,
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# POST /api/slurm/associations  -> sacctmgr -i add user <user> account=<account> [partition=] [qos=]
# ============================================
@slurm_account_bp.route('/associations', methods=['POST'])
@jwt_required
@permission_required('admin')
def slurm_association_add():
    """sacctmgr -i add user <user> account=<account>. dry_run 기본 True."""
    try:
        body = request.get_json(silent=True) or {}
        user = (body.get('user') or '').strip()
        account = (body.get('account') or '').strip()
        if not user:
            return jsonify({'success': False, 'error': "'user' is required"}), 400
        if not account:
            return jsonify({'success': False, 'error': "'account' is required"}), 400

        partition = (body.get('partition') or '').strip()
        qos = (body.get('qos') or '').strip()
        dry_run = bool(body.get('dry_run', True))

        args = ['-i', 'add', 'user', user, f'account={account}']
        if partition:
            args.append(f'partition={partition}')
        if qos:
            args.append(f'qos={qos}')
        command = 'sacctmgr ' + ' '.join(args)

        payload, status = _run_sacctmgr_mutation(
            tuple(args), dry_run, command,
            'association.add', f'{user}@{account}',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# DELETE /api/slurm/associations  -> sacctmgr -i delete user <user> account=<account>
# ============================================
@slurm_account_bp.route('/associations', methods=['DELETE'])
@jwt_required
@permission_required('admin')
def slurm_association_delete():
    """sacctmgr -i delete user <user> account=<account>. dry_run 기본 True."""
    try:
        body = request.get_json(silent=True) or {}
        user = (body.get('user') or '').strip()
        account = (body.get('account') or '').strip()
        if not user:
            return jsonify({'success': False, 'error': "'user' is required"}), 400
        if not account:
            return jsonify({'success': False, 'error': "'account' is required"}), 400

        dry_run = bool(body.get('dry_run', True))

        args = ['-i', 'delete', 'user', user, f'account={account}']
        command = 'sacctmgr ' + ' '.join(args)

        payload, status = _run_sacctmgr_mutation(
            tuple(args), dry_run, command,
            'association.delete', f'{user}@{account}',
        )
        return jsonify(payload), status
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
