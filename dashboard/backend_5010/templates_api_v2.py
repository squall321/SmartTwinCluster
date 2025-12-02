"""
Templates API v2
외부 YAML 템플릿 관리 API

엔드포인트:
- GET    /api/jobs/templates              # 템플릿 목록 조회
- GET    /api/jobs/templates/{id}         # 템플릿 상세 조회
- POST   /api/jobs/templates/scan         # 템플릿 스캔 및 DB 동기화
- GET    /api/jobs/templates/export/{id}  # YAML 내보내기
- POST   /api/jobs/templates/import       # YAML 가져오기
- GET    /api/jobs/templates/categories   # 카테고리 목록
- GET    /api/jobs/templates/search       # 템플릿 검색
"""

from flask import Blueprint, jsonify, request, Response, g
from template_loader import TemplateLoader
from template_validator import TemplateValidator
from template_watcher import get_watcher_status
from apptainer_service_v2 import ApptainerRegistryService
from middleware.jwt_middleware import jwt_required, optional_jwt
import logging
import sqlite3
import os
import yaml

# Blueprint 생성 (v2를 메인 API로 사용)
templates_v2_bp = Blueprint('templates_v2', __name__, url_prefix='/api/jobs/templates')

# 로깅 설정
logger = logging.getLogger(__name__)


def get_db_connection():
    """DB 연결 가져오기"""
    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def get_template_loader():
    """TemplateLoader 인스턴스 생성"""
    db_conn = get_db_connection()
    return TemplateLoader(base_path="/shared/templates", db_connection=db_conn)


@templates_v2_bp.route('', methods=['GET'])
def list_templates():
    """
    템플릿 목록 조회

    Query Parameters:
        category (str): 카테고리 필터 (ml, cfd, structural 등)
        source (str): 소스 필터 (official, community, private)
        tags (str): 쉼표로 구분된 태그

    Returns:
        JSON: {
            "templates": [...],
            "total": int
        }
    """
    try:
        loader = get_template_loader()

        category = request.args.get('category')
        source = request.args.get('source')
        tags = request.args.get('tags', '').split(',') if request.args.get('tags') else None

        # 템플릿 스캔
        templates = loader.scan_templates(category=category, source=source)

        # 태그 필터링
        if tags:
            templates = [
                t for t in templates
                if any(tag in t.get('template', {}).get('tags', []) for tag in tags)
            ]

        return jsonify({
            'templates': templates,
            'total': len(templates)
        }), 200

    except Exception as e:
        logger.error(f"Failed to list templates: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('', methods=['POST'])
@jwt_required
def create_template():
    """
    새 템플릿 생성

    Request Body:
        {
            "yaml": "템플릿 YAML 문자열"
        }

    Returns:
        JSON: {
            "message": str,
            "file_path": str,
            "template_id": str
        }
    """
    try:
        # 사용자 정보 가져오기
        user = g.get('user')
        username = user.get('username', 'anonymous') if user else 'anonymous'
        user_permissions = user.get('permissions', []) if user else []

        data = request.get_json()
        if not data or 'yaml' not in data:
            return jsonify({'error': 'YAML content required'}), 400

        # YAML 파싱
        template_data = yaml.safe_load(data['yaml'])

        # Official 템플릿 생성 시도 시 admin 권한 필요
        source = template_data.get('template', {}).get('source', '')
        if source == 'official':
            if 'admin' not in user_permissions:
                logger.warning(f"User {username} attempted to create official template without admin permission")
                return jsonify({
                    'error': 'Insufficient permissions',
                    'message': 'Only users with admin permission can create official templates'
                }), 403
            logger.info(f"Admin user {username} creating official template")

        # 템플릿 저장
        loader = get_template_loader()
        is_public = template_data.get('template', {}).get('is_public', False)
        file_path = loader.save_template(template_data, username, is_public)

        # DB 동기화
        loader.sync_to_database()

        template_id = template_data.get('template', {}).get('id')
        response_data = {
            'message': 'Template created successfully',
            'file_path': str(file_path),
            'template_id': template_id
        }

        logger.info(f"Template created: {template_id}, response: {response_data}")

        return jsonify(response_data), 201

    except Exception as e:
        logger.error(f"Failed to create template: {e}")
        return jsonify({'error': str(e)}), 400


@templates_v2_bp.route('/<template_id>', methods=['GET'])
def get_template(template_id: str):
    """
    템플릿 상세 조회 (정규화 포함)

    Args:
        template_id: 템플릿 ID

    Returns:
        JSON: {
            ...template YAML 전체...,
            "apptainer_normalized": {
                "mode": "partition" | "specific" | "any" | "fixed",
                "partition": "compute" | "viz",
                "allowed_images": [...],
                "user_selectable": true/false,
                "bind": [...],
                "env": {...}
            }
        }
    """
    try:
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': 'Template not found'}), 404

        # ✅ Template 정규화 추가 (Phase 1)
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            # 검증 실패 시 경고 로그 + 원본 반환 (하위 호환)
            logger.warning(f"Template {template_id} validation failed: {errors}")
            return jsonify(template), 200  # 원본 반환

        # ✅ 정규화된 Template 반환
        logger.info(f"Template {template_id} normalized successfully. Mode: {normalized_template.get('apptainer_normalized', {}).get('mode')}")
        return jsonify(normalized_template), 200

    except Exception as e:
        logger.error(f"Failed to get template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/scan', methods=['POST'])
def scan_templates():
    """
    템플릿 디렉토리 스캔 및 DB 동기화

    Request Body:
        {
            "force": bool  # 강제 동기화 (선택)
        }

    Returns:
        JSON: {
            "message": str,
            "stats": {
                "inserted": int,
                "updated": int,
                "deleted": int
            }
        }
    """
    try:
        loader = get_template_loader()

        # DB 동기화 실행
        stats = loader.sync_to_database()

        return jsonify({
            'message': 'Templates scanned and synced successfully',
            'stats': stats
        }), 200

    except Exception as e:
        logger.error(f"Failed to scan templates: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/export/<template_id>', methods=['GET'])
def export_template(template_id: str):
    """
    템플릿을 YAML 파일로 내보내기

    Args:
        template_id: 템플릿 ID

    Returns:
        YAML 파일 다운로드
    """
    try:
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': 'Template not found'}), 404

        # YAML 변환
        yaml_content = yaml.dump(
            template,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False
        )

        return Response(
            yaml_content,
            mimetype='application/x-yaml',
            headers={
                'Content-Disposition': f'attachment;filename={template_id}.yaml'
            }
        )

    except Exception as e:
        logger.error(f"Failed to export template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/import', methods=['POST'])
def import_template():
    """
    YAML 파일을 업로드하여 템플릿 가져오기

    Request:
        - file: YAML 파일 (multipart/form-data)
        - is_public: 공개 여부 (form field)
        - user_id: 사용자 ID (form field)

    Returns:
        JSON: {
            "message": str,
            "file_path": str,
            "template_id": str
        }
    """
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No file provided'}), 400

        file = request.files['file']
        is_public = request.form.get('is_public', 'false').lower() == 'true'
        user_id = request.form.get('user_id', 'anonymous')

        # YAML 파싱
        template_data = yaml.safe_load(file.read())

        # 템플릿 저장
        loader = get_template_loader()
        file_path = loader.save_template(template_data, user_id, is_public)

        # DB 동기화
        loader.sync_to_database()

        return jsonify({
            'message': 'Template imported successfully',
            'file_path': file_path,
            'template_id': template_data.get('template', {}).get('id')
        }), 201

    except Exception as e:
        logger.error(f"Failed to import template: {e}")
        return jsonify({'error': str(e)}), 400


@templates_v2_bp.route('/categories', methods=['GET'])
def get_categories():
    """
    카테고리 목록 조회

    Returns:
        JSON: {
            "categories": [
                {
                    "name": str,
                    "count": int,
                    "templates": [...]
                }
            ]
        }
    """
    try:
        loader = get_template_loader()
        categories = loader.get_categories()

        return jsonify({
            'categories': categories
        }), 200

    except Exception as e:
        logger.error(f"Failed to get categories: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/search', methods=['GET'])
def search_templates():
    """
    템플릿 검색

    Query Parameters:
        q (str): 검색 키워드
        tags (str): 쉼표로 구분된 태그

    Returns:
        JSON: {
            "query": str,
            "tags": [str],
            "templates": [...],
            "total": int
        }
    """
    try:
        query = request.args.get('q', '')
        tags = request.args.get('tags', '').split(',') if request.args.get('tags') else None

        loader = get_template_loader()
        templates = loader.search_templates(query=query, tags=tags)

        return jsonify({
            'query': query,
            'tags': tags,
            'templates': templates,
            'total': len(templates)
        }), 200

    except Exception as e:
        logger.error(f"Failed to search templates: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/watcher/status', methods=['GET'])
def get_watcher_status_api():
    """
    템플릿 파일 감시자 상태 조회

    Returns:
        JSON: {
            "running": bool,
            "watch_path": str,
            "message": str
        }
    """
    try:
        status = get_watcher_status()
        return jsonify(status), 200

    except Exception as e:
        logger.error(f"Failed to get watcher status: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/<template_id>', methods=['PUT'])
@jwt_required
def update_template(template_id: str):
    """
    템플릿 업데이트

    Args:
        template_id: 템플릿 ID

    Request Body:
        템플릿 YAML 데이터 (JSON)

    Returns:
        JSON: {
            "message": str,
            "template_id": str
        }
    """
    try:
        # 사용자 정보 가져오기
        user = g.get('user')
        username = user.get('username', 'unknown') if user else 'unknown'
        user_permissions = user.get('permissions', []) if user else []

        logger.info(f"Template update requested by {username} (permissions: {user_permissions})")

        # 템플릿 정보 조회하여 source 확인
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': f'Template {template_id} not found'}), 404

        data = request.get_json()

        if not data:
            return jsonify({'error': 'No template data provided'}), 400

        # YAML 문자열인 경우 파싱 (POST와 동일한 방식)
        if 'yaml' in data:
            template_data = yaml.safe_load(data['yaml'])
        else:
            template_data = data

        # Private source인 경우 username 추가
        if template_data.get('template', {}).get('source') == 'private':
            template_data['template']['source'] = f'private:{username}'

        # 권한 체크: 기존 템플릿이 official이거나, 새로운 source가 official인 경우
        old_source = template.get('source', '')
        new_source = template_data.get('template', {}).get('source', old_source)

        # Official 템플릿 수정 또는 Official로 변경 시도 시 admin 권한 필요
        is_modifying_official = 'official' in template.get('file_path', '') or old_source == 'official'
        is_changing_to_official = new_source == 'official'

        if is_modifying_official or is_changing_to_official:
            if 'admin' not in user_permissions:
                logger.warning(f"User {username} attempted to modify/create official template without admin permission")
                logger.warning(f"  Old source: {old_source}, New source: {new_source}")
                return jsonify({
                    'error': 'Insufficient permissions',
                    'message': 'Only users with admin permission can create or modify official templates'
                }), 403
            logger.info(f"Admin user {username} modifying official template {template_id}")

        success = loader.update_template(template_id, template_data, username)

        if success:
            # DB 동기화
            loader.sync_to_database()

            return jsonify({
                'message': 'Template updated successfully',
                'template_id': template_id
            }), 200
        else:
            return jsonify({'error': 'Failed to update template'}), 500

    except PermissionError as e:
        return jsonify({'error': str(e)}), 403
    except ValueError as e:
        return jsonify({'error': str(e)}), 404
    except Exception as e:
        logger.error(f"Failed to update template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/<template_id>', methods=['DELETE'])
@jwt_required
def delete_template(template_id: str):
    """
    템플릿 삭제 (아카이브로 이동)

    Args:
        template_id: 템플릿 ID

    Returns:
        JSON: {
            "message": str,
            "template_id": str
        }
    """
    try:
        # 사용자 정보 가져오기
        user = g.get('user')
        username = user.get('username', 'anonymous') if user else 'anonymous'
        user_permissions = user.get('permissions', []) if user else []

        logger.info(f"Template deletion requested by {username} for {template_id}")

        # 템플릿 정보 조회하여 source 확인
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': f'Template {template_id} not found'}), 404

        # 권한 체크: Official 또는 Community 템플릿 삭제 시 admin 권한 필요
        source = template.get('source', '')
        is_official_or_community = 'official' in template.get('file_path', '') or source in ['official', 'community']

        # Admin 권한 체크 (더 유연하게)
        is_admin = (
            'admin' in user_permissions or
            'administrator' in user_permissions or
            'Admin' in user_permissions or
            username == 'admin' or  # username이 admin인 경우
            any('admin' in perm.lower() for perm in user_permissions)  # 대소문자 구분 없이
        )

        if is_official_or_community:
            if not is_admin:
                logger.warning(f"User {username} (permissions: {user_permissions}) attempted to delete {source} template without admin permission")
                return jsonify({
                    'error': 'Insufficient permissions',
                    'message': 'Only users with admin permission can delete official or community templates'
                }), 403
            logger.info(f"Admin user {username} deleting {source} template {template_id}")

        # Private 템플릿은 소유자만 삭제 가능
        if source.startswith('private:'):
            owner = source.split(':')[1]
            if owner != username and 'admin' not in user_permissions:
                logger.warning(f"User {username} attempted to delete private template owned by {owner}")
                return jsonify({
                    'error': 'Insufficient permissions',
                    'message': 'You can only delete your own private templates'
                }), 403

        # 템플릿 삭제
        success = loader.delete_template(template_id, username)

        if success:
            # DB 동기화
            loader.sync_to_database()

            logger.info(f"Template {template_id} deleted successfully by {username}")
            return jsonify({
                'message': 'Template archived successfully',
                'template_id': template_id
            }), 200
        else:
            return jsonify({'error': 'Failed to delete template'}), 500

    except PermissionError as e:
        logger.warning(f"Permission error deleting template {template_id}: {e}")
        return jsonify({'error': str(e)}), 403
    except ValueError as e:
        logger.warning(f"Template {template_id} not found: {e}")
        return jsonify({'error': str(e)}), 404
    except Exception as e:
        logger.error(f"Failed to delete template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500


@templates_v2_bp.route('/<template_id>/validate', methods=['GET'])
def validate_template(template_id: str):
    """
    템플릿의 Apptainer 이미지 존재 여부 검증

    Args:
        template_id: 템플릿 ID

    Returns:
        JSON: {
            "template_id": str,
            "valid": bool,
            "image_name": str,
            "image_exists": bool,
            "message": str,
            "available_images": [str]  # 사용 가능한 이미지 목록 (이미지 없을 경우)
        }
    """
    try:
        # 템플릿 조회
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': 'Template not found'}), 404

        # Apptainer 이미지 이름 추출
        apptainer_config = template.get('apptainer', {})
        image_name = apptainer_config.get('image_name', '')

        if not image_name:
            return jsonify({
                'template_id': template_id,
                'valid': False,
                'image_name': None,
                'image_exists': False,
                'message': 'Template does not specify an Apptainer image'
            }), 200

        # Apptainer 서비스로 이미지 존재 확인
        db_conn = get_db_connection()
        apptainer_service = ApptainerRegistryService(db_connection=db_conn, redis_client=None)

        all_images = apptainer_service.get_all_images()

        # 이미지 이름으로 검색 (확장자 있는 경우와 없는 경우 모두 처리)
        image_exists = False
        matched_image = None

        for img in all_images:
            img_name = img.get('name', '')
            img_id = img.get('id', '')

            # 정확한 이름 매칭 또는 .sif 제거한 이름 매칭
            if (img_name == image_name or
                img_name == f"{image_name}.sif" or
                img_id == image_name.replace('.sif', '')):
                image_exists = True
                matched_image = img
                break

        if image_exists:
            return jsonify({
                'template_id': template_id,
                'valid': True,
                'image_name': image_name,
                'image_exists': True,
                'image_path': matched_image.get('path'),
                'image_partition': matched_image.get('partition'),
                'message': f'Image "{image_name}" is available in {matched_image.get("partition")} partition'
            }), 200
        else:
            # 사용 가능한 이미지 목록 제공
            available_images = [img.get('name') for img in all_images]

            return jsonify({
                'template_id': template_id,
                'valid': False,
                'image_name': image_name,
                'image_exists': False,
                'message': f'Image "{image_name}" not found in registry',
                'available_images': available_images
            }), 200

    except Exception as e:
        logger.error(f"Failed to validate template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500
