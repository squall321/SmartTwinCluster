"""
Apptainer API Blueprint
Apptainer 이미지 관리를 위한 REST API 엔드포인트

엔드포인트:
- GET  /api/apptainer/images              # 모든 이미지 목록
- GET  /api/apptainer/images/<node>       # 특정 노드 이미지
- GET  /api/apptainer/images/<id>/metadata # 이미지 상세 정보
- GET  /api/apptainer/images/<id>/apps    # 이미지 내부 앱 목록
- POST /api/apptainer/scan                # 전체 노드 스캔 트리거
"""

from flask import Blueprint, jsonify, request, g
from apptainer_service_v2 import ApptainerRegistryService, ApptainerImage
import logging
import sqlite3
import os

# Blueprint 생성
apptainer_bp = Blueprint('apptainer', __name__)

# 로깅 설정
logger = logging.getLogger(__name__)


def get_db_connection():
    """DB 연결 가져오기"""
    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def get_apptainer_service():
    """ApptainerRegistryService 인스턴스 생성"""
    db_conn = get_db_connection()
    # Redis 클라이언트는 나중에 Phase 4에서 추가
    return ApptainerRegistryService(db_connection=db_conn, redis_client=None)


@apptainer_bp.route('/api/apptainer/images', methods=['GET'])
def list_images():
    """
    모든 Apptainer 이미지 목록 조회

    Query Parameters:
        partition (str, optional): 파티션 필터 (compute, viz)
        type (str, optional): 이미지 타입 필터 (viz, compute, custom)
        node (str, optional): 특정 노드 필터

    Returns:
        JSON: {
            "images": [
                {
                    "id": "abc123",
                    "name": "vnc_gnome.sif",
                    "path": "/opt/apptainers/vnc_gnome.sif",
                    "node": "viz-node001",
                    "partition": "viz",
                    "type": "viz",
                    "size": 2147483648,
                    "version": "1.0.0",
                    ...
                }
            ],
            "total": 10
        }
    """
    try:
        service = get_apptainer_service()

        # Query parameters
        partition = request.args.get('partition')
        image_type = request.args.get('type')
        node = request.args.get('node')

        # 파티션별 조회 또는 전체 조회
        if partition:
            images = service.get_images_by_partition(partition)
        else:
            images = service.get_all_images()

        # 추가 필터링
        if image_type:
            images = [img for img in images if img.get('type') == image_type]

        if node:
            images = [img for img in images if img.get('node') == node]

        return jsonify({
            'images': images,
            'total': len(images)
        }), 200

    except Exception as e:
        logger.error(f"Failed to list images: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/images/<node_name>', methods=['GET'])
def get_node_images(node_name: str):
    """
    특정 노드의 이미지 목록 조회

    Args:
        node_name: 노드 호스트명 (예: compute-node001)

    Returns:
        JSON: {
            "node": "compute-node001",
            "images": [...],
            "total": 5
        }
    """
    try:
        service = get_apptainer_service()
        images = service.get_all_images()

        # 특정 노드 필터링
        node_images = [img for img in images if img.get('node') == node_name]

        return jsonify({
            'node': node_name,
            'images': node_images,
            'total': len(node_images)
        }), 200

    except Exception as e:
        logger.error(f"Failed to get images for node {node_name}: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/images/<image_id>/metadata', methods=['GET'])
def get_image_metadata(image_id: str):
    """
    이미지 상세 메타데이터 조회

    Args:
        image_id: 이미지 ID

    Returns:
        JSON: {
            "id": "abc123",
            "name": "vnc_gnome.sif",
            "path": "/opt/apptainers/vnc_gnome.sif",
            "node": "viz-node001",
            "partition": "viz",
            "type": "viz",
            "size": 2147483648,
            "version": "1.0.0",
            "description": "VNC with GNOME desktop",
            "labels": {"gpu": "optional", "display": "required"},
            "apps": ["python", "gedit", "firefox"],
            "runscript": "#!/bin/bash\n...",
            "env_vars": {"PATH": "/usr/local/bin:..."},
            "created_at": "2025-11-05T10:00:00",
            "updated_at": "2025-11-05T10:00:00",
            "last_scanned": "2025-11-05T10:00:00",
            "is_active": true
        }
    """
    try:
        service = get_apptainer_service()

        # DB에서 이미지 조회
        all_images = service.get_all_images()
        image = next((img for img in all_images if img['id'] == image_id), None)

        if not image:
            return jsonify({'error': 'Image not found'}), 404

        return jsonify(image), 200

    except Exception as e:
        logger.error(f"Failed to get metadata for image {image_id}: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/images/<image_id>/apps', methods=['GET'])
def get_image_apps(image_id: str):
    """
    이미지 내부 앱 목록 조회

    Args:
        image_id: 이미지 ID

    Returns:
        JSON: {
            "image_id": "abc123",
            "image_name": "vnc_gnome.sif",
            "apps": ["python", "gedit", "firefox"]
        }
    """
    try:
        service = get_apptainer_service()

        # DB에서 이미지 조회
        all_images = service.get_all_images()
        image = next((img for img in all_images if img['id'] == image_id), None)

        if not image:
            return jsonify({'error': 'Image not found'}), 404

        return jsonify({
            'image_id': image['id'],
            'image_name': image['name'],
            'apps': image.get('apps', [])
        }), 200

    except Exception as e:
        logger.error(f"Failed to get apps for image {image_id}: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/scan', methods=['POST'])
def scan_all_nodes():
    """
    중앙 레지스트리의 Apptainer 이미지 스캔

    Request Body:
        {
            "partitions": ["compute", "viz", "shared"],  # optional, 특정 파티션만 스캔
            "force": false  # optional, 강제 재스캔 (캐시 무시)
        }

    Returns:
        JSON: {
            "message": "Scan completed",
            "stats": {
                "compute": 2,
                "viz": 0,
                "shared": 0
            },
            "scanned_partitions": ["compute", "viz", "shared"]
        }

    Note:
        중앙 레지스트리 (/shared/apptainer/images/)를 스캔하여
        실제 존재하는 이미지만 DB에 저장합니다.
    """
    try:
        service = get_apptainer_service()

        # Request body 파싱
        data = request.get_json() or {}
        target_partitions = data.get('partitions', ['compute', 'viz', 'shared'])
        force = data.get('force', False)

        # 파티션별 스캔
        stats = {}
        for partition in target_partitions:
            if partition in service.partitions:
                images = service.scan_partition_images(partition)

                # DB에 저장
                saved_count = 0
                for image in images:
                    if service._save_image_to_db(image):
                        saved_count += 1

                stats[partition] = saved_count
                logger.info(f"Scanned {partition}: {saved_count} images")
            else:
                logger.warning(f"Unknown partition: {partition}")
                stats[partition] = 0

        return jsonify({
            'message': 'Scan completed',
            'stats': stats,
            'scanned_partitions': target_partitions
        }), 200

    except Exception as e:
        logger.error(f"Failed to scan partitions: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/partitions', methods=['GET'])
def get_partitions_summary():
    """
    파티션별 이미지 통계

    Returns:
        JSON: {
            "partitions": [
                {
                    "name": "compute",
                    "total_images": 5,
                    "nodes": ["compute-node001"],
                    "types": {"compute": 4, "custom": 1}
                },
                {
                    "name": "viz",
                    "total_images": 3,
                    "nodes": ["viz-node001"],
                    "types": {"viz": 3}
                }
            ]
        }
    """
    try:
        service = get_apptainer_service()
        all_images = service.get_all_images()

        # 파티션별 그룹화
        partitions = {}
        for img in all_images:
            partition = img.get('partition', 'unknown')
            if partition not in partitions:
                partitions[partition] = {
                    'name': partition,
                    'total_images': 0,
                    'nodes': set(),
                    'types': {}
                }

            partitions[partition]['total_images'] += 1
            partitions[partition]['nodes'].add(img.get('node'))

            img_type = img.get('type', 'custom')
            partitions[partition]['types'][img_type] = \
                partitions[partition]['types'].get(img_type, 0) + 1

        # set을 list로 변환
        result = []
        for partition_data in partitions.values():
            partition_data['nodes'] = list(partition_data['nodes'])
            result.append(partition_data)

        return jsonify({'partitions': result}), 200

    except Exception as e:
        logger.error(f"Failed to get partitions summary: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/search', methods=['GET'])
def search_images():
    """
    이미지 검색

    Query Parameters:
        q (str): 검색 키워드 (이름, 설명에서 검색)
        tags (str): 쉼표로 구분된 태그 (labels에서 검색)

    Returns:
        JSON: {
            "query": "python",
            "images": [...],
            "total": 3
        }
    """
    try:
        service = get_apptainer_service()

        query = request.args.get('q', '').lower()
        tags = request.args.get('tags', '').split(',') if request.args.get('tags') else []

        # 전체 이미지 조회
        all_images = service.get_all_images()

        # 검색 필터링
        results = []
        for img in all_images:
            # 키워드 검색
            if query:
                name_match = query in img.get('name', '').lower()
                desc_match = query in img.get('description', '').lower()
                if not (name_match or desc_match):
                    continue

            # 태그 검색
            if tags:
                img_labels = img.get('labels', {})
                if not any(tag in img_labels for tag in tags):
                    continue

            results.append(img)

        return jsonify({
            'query': query,
            'tags': tags,
            'images': results,
            'total': len(results)
        }), 200

    except Exception as e:
        logger.error(f"Failed to search images: {e}")
        return jsonify({'error': str(e)}), 500


@apptainer_bp.route('/api/apptainer/validate/<image_id>', methods=['POST'])
def validate_image(image_id: str):
    """
    이미지 유효성 검증 (실제 파일 존재 여부 확인)

    Args:
        image_id: 이미지 ID

    Returns:
        JSON: {
            "image_id": "abc123",
            "valid": true,
            "message": "Image file exists on node"
        }
    """
    try:
        service = get_apptainer_service()

        # DB에서 이미지 조회
        all_images = service.get_all_images()
        image = next((img for img in all_images if img['id'] == image_id), None)

        if not image:
            return jsonify({'error': 'Image not found in database'}), 404

        # 로컬 파일 존재 확인
        import os
        is_valid = os.path.exists(image['path'])

        return jsonify({
            'image_id': image_id,
            'valid': is_valid,
            'path': image['path'],
            'message': 'Image file exists in registry' if is_valid else 'Image file not found in registry'
        }), 200

    except Exception as e:
        logger.error(f"Failed to validate image {image_id}: {e}")
        return jsonify({'error': str(e)}), 500
