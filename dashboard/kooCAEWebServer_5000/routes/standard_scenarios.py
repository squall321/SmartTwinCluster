"""
Standard Scenarios API Routes
표준 규격 시나리오 API 엔드포인트
"""
from flask import Blueprint, jsonify, request
import json
import os
from pathlib import Path
from models.standard_scenario import StandardScenario, StandardScenarioSummary

# Blueprint 생성
standard_scenarios_bp = Blueprint('standard_scenarios', __name__, url_prefix='/api/standard-scenarios')

# 시나리오 데이터 디렉토리 경로
SCENARIOS_DIR = Path(__file__).parent.parent / "data" / "standard_scenarios"


@standard_scenarios_bp.route('/', methods=['GET'])
def get_standard_scenarios():
    """
    모든 규격 시나리오 목록 조회

    Returns:
        JSON: 규격 시나리오 요약 목록
    """
    try:
        scenarios = []

        # 디렉토리가 존재하지 않으면 생성
        if not SCENARIOS_DIR.exists():
            SCENARIOS_DIR.mkdir(parents=True, exist_ok=True)
            return jsonify({'scenarios': []}), 200

        # 모든 JSON 파일 읽기
        for file_path in sorted(SCENARIOS_DIR.glob("*.json")):
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)

                    # 요약 정보 생성
                    summary = StandardScenarioSummary(
                        id=data['id'],
                        name=data['name'],
                        category=data['category'],
                        description=data['description'],
                        version=data['version'],
                        angleCount=len(data['angles'])
                    )
                    scenarios.append(summary.to_dict())
            except Exception as e:
                print(f"Error loading scenario file {file_path}: {e}")
                continue

        return jsonify({'scenarios': scenarios}), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@standard_scenarios_bp.route('/<scenario_id>', methods=['GET'])
def get_standard_scenario(scenario_id):
    """
    특정 규격 시나리오 상세 조회

    Args:
        scenario_id: 시나리오 ID

    Returns:
        JSON: 규격 시나리오 상세 정보
    """
    try:
        file_path = SCENARIOS_DIR / f"{scenario_id}.json"

        if not file_path.exists():
            return jsonify({'error': f'Scenario "{scenario_id}" not found'}), 404

        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        scenario = StandardScenario.from_dict(data)
        return jsonify({'scenario': scenario.to_dict()}), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@standard_scenarios_bp.route('/categories', methods=['GET'])
def get_categories():
    """
    사용 가능한 시나리오 카테고리 목록 조회

    Returns:
        JSON: 카테고리 목록
    """
    try:
        categories = set()

        if not SCENARIOS_DIR.exists():
            return jsonify({'categories': []}), 200

        for file_path in SCENARIOS_DIR.glob("*.json"):
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    categories.add(data['category'])
            except Exception as e:
                print(f"Error loading scenario file {file_path}: {e}")
                continue

        category_list = [
            {'id': cat, 'name': get_category_name(cat)}
            for cat in sorted(categories)
        ]

        return jsonify({'categories': category_list}), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500


def get_category_name(category_id):
    """카테고리 ID를 한글 이름으로 변환"""
    category_names = {
        'fall_test': '낙하 시험',
        'cumulative_test': '누적 시험',
        'impact_test': '충격 시험',
        'attitude_test': '자세 시험',
        'rotation_test': '회전 시험'
    }
    return category_names.get(category_id, category_id)


# Health check endpoint
@standard_scenarios_bp.route('/health', methods=['GET'])
def health_check():
    """
    API 헬스 체크
    """
    scenarios_count = len(list(SCENARIOS_DIR.glob("*.json"))) if SCENARIOS_DIR.exists() else 0
    return jsonify({
        'status': 'healthy',
        'scenarios_directory': str(SCENARIOS_DIR),
        'scenarios_count': scenarios_count
    }), 200
