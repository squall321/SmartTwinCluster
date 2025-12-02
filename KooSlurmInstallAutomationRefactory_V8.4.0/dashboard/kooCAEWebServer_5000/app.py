from flask import Flask
from flask_cors import CORS
from flask_sock import Sock
from models.user import db
from config import Config
from routes import register_routes
from routes.vnc_proxy import vnc_proxy_bp, register_websocket_proxy
import os

def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    '''CORS(app, resources={r"/api/*": {"origins": [
        "http://219.250.247.155:5173",
        "http://localhost:5173"
    ]}}, supports_credentials=True)
    '''
        # CORS 정확히 명시 (React 앱 IP 포함)
    CORS(app, resources={r"/api/*": {"origins": Config.CORS_ORIGINS}}, supports_credentials=True)
    # VNC 프록시도 CORS 허용
    CORS(app, resources={r"/vnc/*": {"origins": Config.CORS_ORIGINS}}, supports_credentials=True)


    db.init_app(app)
    os.makedirs(os.path.dirname(Config.SQLALCHEMY_DATABASE_URI.replace("sqlite:///", "")), exist_ok=True)

    @app.before_request
    def create_tables():
        db.create_all()

    register_routes(app)

    # VNC 프록시 라우트 등록
    app.register_blueprint(vnc_proxy_bp)

    # WebSocket 지원 추가
    sock = Sock(app)
    register_websocket_proxy(sock, app)

    return app

if __name__ == '__main__':
    app = create_app()
    app.run(host='0.0.0.0', port=5000, debug=True)
 