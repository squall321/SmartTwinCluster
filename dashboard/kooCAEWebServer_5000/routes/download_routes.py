# download_routes.py

import os
from flask import Blueprint, jsonify, send_from_directory, current_app, abort
from flask_cors import cross_origin
download_bp = Blueprint('download', __name__)

@download_bp.route('/api/impactors', methods=['POST'])  # 꼭 POST로
def download_stl_impactor():
    import os
    from flask import current_app, jsonify

    stl_dir = os.path.join(current_app.root_path, 'source', 'stl', 'impactor')

    try:
        files = [
            {
                "name": filename,
                "url": f"/api/impactors/download/{filename}"
            }
            for filename in os.listdir(stl_dir)
            if filename.endswith('.stl')
        ]
        return jsonify({"success": True, "files": files})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@download_bp.route('/api/impactors/download/<path:filename>', methods=['GET'])
@cross_origin()
def serve_stl_file(filename):
    import os
    stl_dir = os.path.join(current_app.root_path, 'source', 'stl', 'impactor')
    file_path = os.path.join(stl_dir, filename)

    if not os.path.exists(file_path):
        return abort(404, description=f"{filename} not found in {stl_dir}")

    return send_from_directory(stl_dir, filename, mimetype='application/octet-stream')


@download_bp.route('/api/materials/display', methods=['GET'])
@cross_origin()
def get_display_material():
    material_dir = os.path.join(current_app.root_path, 'source', 'material')
    filename = 'DisplayMaterial.txt'
    file_path = os.path.join(material_dir, filename)

    if not os.path.exists(file_path):
        return abort(404, description="DisplayMaterial.txt not found")

    return send_from_directory(material_dir, filename, mimetype='text/plain')

@download_bp.route('/api/materials/all', methods=['POST'])  # 반드시 POST
@cross_origin()
def list_all_materials():
    material_dir = os.path.join(current_app.root_path, 'source', 'material')

    try:
        files = [
            {
                "name": filename,
                "url": f"/api/materials/download/{filename}"
            }
            for filename in os.listdir(material_dir)
            if filename.endswith('.txt')
        ]
        return jsonify({"success": True, "files": files})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@download_bp.route('/api/materials/download/<path:filename>', methods=['GET'])
@cross_origin()
def download_material_file(filename):
    material_dir = os.path.join(current_app.root_path, 'source', 'material')
    file_path = os.path.join(material_dir, filename)

    if not os.path.exists(file_path):
        return abort(404, description=f"{filename} not found in {material_dir}")

    return send_from_directory(material_dir, filename, mimetype='text/plain')