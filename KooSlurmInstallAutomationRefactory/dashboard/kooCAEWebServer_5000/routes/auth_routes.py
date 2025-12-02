from flask import Blueprint, request, jsonify
from models.user import db, User
from werkzeug.security import generate_password_hash, check_password_hash

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(username=data['username']).first()
    if user and check_password_hash(user.password, data['password']):
        return jsonify({"success": True})
    return jsonify({"success": False, "message": "아이디 또는 비밀번호가 틀렸습니다."}), 401

@auth_bp.route('/api/signup', methods=['POST'])
def signup():
    data = request.get_json()
    if User.query.filter((User.username == data['username']) | (User.email == data['email'])).first():
        return jsonify({"success": False, "message": "이미 존재하는 아이디 또는 이메일입니다."}), 409

    hashed_pw = generate_password_hash(data['password'])
    user = User(
        username=data['username'],
        email=data['email'],
        password=hashed_pw,
        name=data['name'],
        department=data.get('department', '')
    )
    db.session.add(user)
    db.session.commit()
    return jsonify({"success": True}), 201
