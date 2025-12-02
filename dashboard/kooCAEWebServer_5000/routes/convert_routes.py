import os
from flask import Blueprint, request, jsonify, send_file, g
from werkzeug.utils import secure_filename
from middleware.jwt_middleware import jwt_required
from services.geom_writer import write_stl_from_elements, write_glb_from_elements, write_glb_from_elements_prev
from services.file_parser import parse_kfile, get_boundary_box_of_given_partid

convert_bp = Blueprint('convert', __name__)
UPLOAD_ROOT = "uploads"

@convert_bp.route('/api/convert_kfile_to_stl', methods=['POST'])
@jwt_required
def convert_kfile_to_stl():
    # write consol log
    if 'file' not in request.files or 'partid' not in request.form:
        return jsonify({'error': '파일과 파트 ID가 필요합니다.'}), 400
    file = request.files['file']
    part_id = request.form['partid']
    print(file)
    print(part_id)
    filename = secure_filename(file.filename or "unnamed_file")
    print(f"filename: {filename}")

    # JWT에서 사용자명 가져오기
    username = g.user.get('username')
    print(f"username (from JWT): {username}")

    # 사용자별 폴더 생성
    user_folder = os.path.join(UPLOAD_ROOT, secure_filename(username))
    os.makedirs(user_folder, exist_ok=True)

    file_path = os.path.join(user_folder, filename)
    file.save(file_path)
    print(f"file_path: {file_path}")
    try:
        nodes, elements, types = parse_kfile(file_path, part_id)
        
        if not elements:
            return jsonify({'error': '파트 ID에 해당하는 요소가 없습니다.'}), 404
        base_name = os.path.splitext(filename)[0]
        out_path = os.path.join(user_folder, f"{base_name}_{part_id}.stl")

        write_stl_from_elements(nodes, elements, types, out_path)
        
        return send_file(out_path, as_attachment=True, download_name=f"{base_name}_{part_id}.stl")

    except Exception as e:
        return jsonify({'error': f'STL 변환 중 오류 발생: {str(e)}'}), 500
                
@convert_bp.route('/api/convert_kfile_to_glb', methods=['POST'])
@jwt_required
def convert_kfile_to_glb():
    if 'file' not in request.files or 'partid' not in request.form:
        return jsonify({'error': '파일과 파트 ID가 필요합니다.'}), 400

    file = request.files['file']
    part_id = request.form['partid']
    filename = secure_filename(file.filename or "unnamed_file")

    # JWT에서 사용자명 가져오기
    username = g.user.get('username')

    # 사용자별 폴더 생성
    user_folder = os.path.join(UPLOAD_ROOT, secure_filename(username))
    os.makedirs(user_folder, exist_ok=True)

    file_path = os.path.join(user_folder, filename)
    file.save(file_path)

    try:
        nodes, elements, types = parse_kfile(file_path, part_id)
        if not elements:
            return jsonify({'error': '파트 ID에 해당하는 요소가 없습니다.'}), 404

        base_name = os.path.splitext(filename)[0]
        out_path = os.path.join(user_folder, f"{base_name}_{part_id}.glb")
        # ✅ 강제 변환
        '''elements = {int(k): v for k, v in elements.items()}
        types = {int(k): v for k, v in types.items()}
        # elements의 각 conn 리스트를 max 4개로 잘라줌
        cleaned_elements = {}
        for eid, conn in elements.items():
            if isinstance(conn, list) and len(conn) >= 4:
                cleaned_elements[eid] = conn[:4]  # tet4 기준'''
        # ✅ GLB 저장 함수 호출
        write_glb_from_elements(nodes, elements, types, out_path)

        return send_file(out_path, as_attachment=True, download_name=f"{base_name}_{part_id}.glb")

    except Exception as e:
        return jsonify({'error': f'GLB 변환 중 오류 발생: {str(e)}'}), 500


@convert_bp.route('/api/get_boundary_box_of_partid', methods=['POST'])
@jwt_required
def get_boundary_box_of_partid():
    if 'file' not in request.files or 'partid' not in request.form:
        return jsonify({'error': '파일과 파트 ID가 필요합니다.'}), 400
    file = request.files['file']
    part_id = request.form['partid']
    filename = secure_filename(file.filename or "unnamed_file")

    # JWT에서 사용자명 가져오기
    username = g.user.get('username')
    file_path = os.path.join(UPLOAD_ROOT, secure_filename(username), filename)
    min_x, max_x, min_y, max_y, min_z, max_z = get_boundary_box_of_given_partid(file_path, part_id)
    return jsonify({'min_x': min_x, 'max_x': max_x, 'min_y': min_y, 'max_y': max_y, 'min_z': min_z, 'max_z': max_z})