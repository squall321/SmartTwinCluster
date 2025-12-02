from flask import Blueprint, jsonify

sim_bp = Blueprint('sim', __name__)

@sim_bp.route('/api/full_angle_drop', methods=['GET'])
def full_angle_drop():
    return {'success': True, 'message': '전각도 낙하 시뮬레이션 API입니다.'}
