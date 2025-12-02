# Phase 1: Auth Portal 개발 (SAML SSO + JWT)

**기간**: 2-3주 (10-15일)
**목표**: SAML 2.0 SSO 인증 및 JWT 토큰 발급 시스템 구축
**선행 조건**: Phase 0 완료
**담당자**: Backend 개발자 + Frontend 개발자

---

## 📋 목차

1. [개요](#개요)
2. [Week 1: Auth Backend 개발](#week-1-auth-backend-개발)
3. [Week 2: Auth Frontend 개발](#week-2-auth-frontend-개발)
4. [Week 3: 통합 및 테스트](#week-3-통합-및-테스트)
5. [검증 체크리스트](#검증-체크리스트)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

### 목적
Phase 1은 전체 시스템의 중앙 인증 시스템을 구축하는 단계입니다. SAML 2.0 SSO를 통한 사용자 인증과 JWT 토큰 발급을 구현합니다.

### 아키텍처 개요
```
User → Nginx (443) → Auth Frontend (4431)
                         ↓
                    SAML SSO Login
                         ↓
                    saml-idp (7000)
                         ↓
                    Auth Backend (4430)
                         ↓
                    JWT Token + Redis Session
                         ↓
                    ServiceMenu (서비스 선택)
```

### 주요 작업
1. ✅ Auth Backend (Flask + python3-saml + PyJWT)
2. ✅ Auth Frontend (React + TypeScript + Vite)
3. ✅ SAML 인증 통합
4. ✅ JWT 토큰 발급 및 검증
5. ✅ Redis 세션 관리
6. ✅ ServiceMenu (그룹 기반 서비스 선택)

### 성공 기준
- [ ] saml-idp로 SSO 로그인 성공
- [ ] JWT 토큰 발급 확인 (페이로드 검증)
- [ ] ServiceMenu에서 그룹별 서비스 목록 표시
- [ ] Redis에 세션 저장 확인
- [ ] JWT 검증 API (`/auth/verify`) 정상 동작

---

## Week 1: Auth Backend 개발

### Day 1-2: 프로젝트 구조 및 SAML 설정

#### 🎯 목표
Flask 프로젝트 생성 및 SAML 인증 설정

#### Step 1.1: 프로젝트 디렉토리 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
mkdir -p auth_portal_4430
cd auth_portal_4430

# 디렉토리 구조 생성
mkdir -p saml/certs saml/metadata config logs

# .gitignore 생성
cat > .gitignore << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
.env
venv/
*.log
saml/certs/*.key
saml/certs/*.pem
.DS_Store
EOF
```

#### Step 1.2: 가상 환경 및 패키지 설치
```bash
# Python 가상 환경 생성
python3 -m venv venv
source venv/bin/activate

# 필수 패키지 설치
pip install --upgrade pip
pip install flask==3.0.0
pip install python3-saml==1.15.0
pip install PyJWT==2.8.0
pip install redis==5.0.0
pip install flask-cors==4.0.0
pip install python-dotenv==1.0.0

# 개발 도구
pip install pytest==7.4.0
pip install black==23.9.1
pip install flake8==6.1.0

# requirements.txt 생성
pip freeze > requirements.txt
```

#### Step 1.3: 환경 변수 설정
```bash
cat > .env << 'EOF'
# Flask Configuration
FLASK_APP=app.py
FLASK_ENV=development
FLASK_DEBUG=1
SECRET_KEY=your_super_secret_key_change_this_in_production_min_512_bits

# JWT Configuration
JWT_SECRET_KEY=your_jwt_secret_key_must_be_512_bits_or_more_for_hs256
JWT_ALGORITHM=HS256
JWT_EXPIRATION_HOURS=1

# Redis Configuration
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# SAML Configuration
SAML_IDP_METADATA_URL=http://localhost:7000/metadata
SAML_SP_ENTITY_ID=auth-portal
SAML_ACS_URL=http://localhost:4430/auth/saml/acs
SAML_SLO_URL=http://localhost:4430/auth/saml/slo

# Server Configuration
HOST=0.0.0.0
PORT=4430

# CORS
CORS_ORIGINS=http://localhost:4431,https://localhost
EOF

# 보안을 위해 .env 파일 권한 설정
chmod 600 .env
```

#### Step 1.4: SP 인증서 생성
```bash
cd saml/certs

# Service Provider 인증서 및 개인키 생성 (10년 유효)
openssl req -x509 -newkey rsa:2048 -keyout sp.key -out sp.crt \
  -days 3650 -nodes \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/OU=Auth Portal/CN=auth-portal-sp"

# 권한 설정
chmod 600 sp.key
chmod 644 sp.crt

# 인증서 정보 확인
openssl x509 -in sp.crt -noout -text | grep -E "Subject:|Issuer:|Not"

cd ../..
```

#### Step 1.5: IdP 메타데이터 다운로드
```bash
# SAML-IdP에서 메타데이터 다운로드
curl -s http://localhost:7000/metadata > saml/metadata/idp_metadata.xml

# 다운로드 확인
cat saml/metadata/idp_metadata.xml | head -20

# EntityDescriptor 확인
grep "<EntityDescriptor" saml/metadata/idp_metadata.xml
```

#### Step 1.6: SAML Settings 파일 생성
```bash
cat > saml/settings.json << 'EOF'
{
  "strict": true,
  "debug": true,
  "sp": {
    "entityId": "auth-portal",
    "assertionConsumerService": {
      "url": "http://localhost:4430/auth/saml/acs",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
    },
    "singleLogoutService": {
      "url": "http://localhost:4430/auth/saml/slo",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
    },
    "NameIDFormat": "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
    "x509cert": "",
    "privateKey": ""
  },
  "idp": {
    "entityId": "http://localhost:7000/metadata",
    "singleSignOnService": {
      "url": "http://localhost:7000/saml/sso",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
    },
    "singleLogoutService": {
      "url": "http://localhost:7000/saml/slo",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
    },
    "x509cert": ""
  },
  "security": {
    "nameIdEncrypted": false,
    "authnRequestsSigned": false,
    "logoutRequestSigned": false,
    "logoutResponseSigned": false,
    "signMetadata": false,
    "wantMessagesSigned": false,
    "wantAssertionsSigned": false,
    "wantAssertionsEncrypted": false,
    "wantNameIdEncrypted": false,
    "requestedAuthnContext": true,
    "signatureAlgorithm": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
    "digestAlgorithm": "http://www.w3.org/2001/04/xmlenc#sha256"
  },
  "contactPerson": {
    "technical": {
      "givenName": "IT Support",
      "emailAddress": "it-support@hpc.local"
    },
    "support": {
      "givenName": "HPC Support",
      "emailAddress": "hpc-support@hpc.local"
    }
  },
  "organization": {
    "en-US": {
      "name": "HPC Lab",
      "displayname": "High Performance Computing Laboratory",
      "url": "https://hpc.local"
    }
  }
}
EOF
```

#### ✅ Day 1-2 완료 체크리스트
- [ ] 프로젝트 디렉토리 구조 생성
- [ ] Python 가상 환경 및 패키지 설치
- [ ] .env 환경 변수 파일 생성
- [ ] SP 인증서 생성
- [ ] IdP 메타데이터 다운로드
- [ ] SAML settings.json 생성

---

### Day 3-4: SAML 핸들러 및 JWT 모듈 구현

#### Step 2.1: 설정 모듈 (config.py)
```python
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')
    DEBUG = os.getenv('FLASK_DEBUG', '0') == '1'
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', 4430))

    # JWT
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'jwt-secret-key-512-bits-minimum')
    JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')
    JWT_EXPIRATION_HOURS = int(os.getenv('JWT_EXPIRATION_HOURS', 1))

    # Redis
    REDIS_HOST = os.getenv('REDIS_HOST', '127.0.0.1')
    REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
    REDIS_DB = int(os.getenv('REDIS_DB', 0))
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', '')

    # SAML
    SAML_PATH = os.path.join(os.path.dirname(__file__), 'saml')
    SAML_SETTINGS_PATH = os.path.join(SAML_PATH, 'settings.json')
    SAML_IDP_METADATA_PATH = os.path.join(SAML_PATH, 'metadata', 'idp_metadata.xml')

    # CORS
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', 'http://localhost:4431').split(',')

    # Groups to Permissions Mapping
    PERMISSIONS_MAP = {
        'HPC-Admins': [
            'dashboard.view', 'dashboard.admin',
            'jobs.submit', 'jobs.cancel_all',
            'vnc.create', 'vnc.delete_all',
            'cae.execute',
            'users.manage', 'system.config'
        ],
        'HPC-Users': [
            'dashboard.view',
            'jobs.submit', 'jobs.cancel_own',
            'vnc.create', 'vnc.delete_own'
        ],
        'GPU-Users': [
            'vnc.create', 'vnc.delete_own'
        ],
        'Automation-Users': [
            'cae.execute'
        ]
    }

    @staticmethod
    def get_permissions_for_groups(groups):
        """그룹 목록에서 권한 목록 생성"""
        permissions = set()
        for group in groups:
            if group in Config.PERMISSIONS_MAP:
                permissions.update(Config.PERMISSIONS_MAP[group])
        return list(permissions)
```

#### Step 2.2: SAML 핸들러 (saml_handler.py)
```python
# saml_handler.py
import json
from onelogin.saml2.auth import OneLogin_Saml2_Auth
from onelogin.saml2.utils import OneLogin_Saml2_Utils
from config import Config

class SAMLHandler:
    @staticmethod
    def load_saml_settings():
        """SAML 설정 파일 로드"""
        with open(Config.SAML_SETTINGS_PATH, 'r') as f:
            settings = json.load(f)

        # SP 인증서 로드
        sp_cert_path = os.path.join(Config.SAML_PATH, 'certs', 'sp.crt')
        sp_key_path = os.path.join(Config.SAML_PATH, 'certs', 'sp.key')

        with open(sp_cert_path, 'r') as f:
            settings['sp']['x509cert'] = f.read()

        with open(sp_key_path, 'r') as f:
            settings['sp']['privateKey'] = f.read()

        # IdP 인증서 로드 (메타데이터에서 추출)
        with open(Config.SAML_IDP_METADATA_PATH, 'r') as f:
            idp_metadata = f.read()
            # IdP 인증서 추출 (간단한 파싱)
            import re
            cert_match = re.search(r'<X509Certificate>(.*?)</X509Certificate>',
                                   idp_metadata, re.DOTALL)
            if cert_match:
                settings['idp']['x509cert'] = cert_match.group(1).strip()

        return settings

    @staticmethod
    def prepare_flask_request(request):
        """Flask request를 SAML 라이브러리 형식으로 변환"""
        url_data = {
            'https': 'on' if request.scheme == 'https' else 'off',
            'http_host': request.host,
            'script_name': request.path,
            'server_port': request.environ.get('SERVER_PORT', '80'),
            'get_data': request.args.copy(),
            'post_data': request.form.copy()
        }
        return url_data

    @staticmethod
    def init_saml_auth(request):
        """SAML Auth 객체 초기화"""
        saml_settings = SAMLHandler.load_saml_settings()
        request_data = SAMLHandler.prepare_flask_request(request)
        return OneLogin_Saml2_Auth(request_data, saml_settings)

    @staticmethod
    def get_sso_url(request):
        """SSO 로그인 URL 생성"""
        auth = SAMLHandler.init_saml_auth(request)
        return auth.login()

    @staticmethod
    def process_saml_response(request):
        """SAML Response 처리 및 사용자 속성 추출"""
        auth = SAMLHandler.init_saml_auth(request)
        auth.process_response()

        errors = auth.get_errors()
        if errors:
            error_reason = auth.get_last_error_reason()
            raise Exception(f'SAML Authentication Failed: {error_reason}')

        if not auth.is_authenticated():
            raise Exception('User not authenticated')

        # 사용자 속성 추출
        attributes = auth.get_attributes()
        nameid = auth.get_nameid()

        user_info = {
            'nameid': nameid,
            'email': attributes.get('email', [nameid])[0] if attributes.get('email') else nameid,
            'username': attributes.get('userName', [nameid.split('@')[0]])[0],
            'first_name': attributes.get('firstName', [''])[0],
            'last_name': attributes.get('lastName', [''])[0],
            'display_name': attributes.get('displayName', [nameid])[0],
            'groups': attributes.get('groups', []),
            'department': attributes.get('department', [''])[0]
        }

        return user_info
```

#### Step 2.3: JWT 핸들러 (jwt_handler.py)
```python
# jwt_handler.py
import jwt
from datetime import datetime, timedelta
from config import Config

class JWTHandler:
    @staticmethod
    def create_token(user_info):
        """JWT 토큰 생성"""
        now = datetime.utcnow()
        expiration = now + timedelta(hours=Config.JWT_EXPIRATION_HOURS)

        # 그룹에서 권한 계산
        permissions = Config.get_permissions_for_groups(user_info.get('groups', []))

        payload = {
            'sub': user_info['username'],
            'email': user_info['email'],
            'name': user_info['display_name'],
            'first_name': user_info.get('first_name', ''),
            'last_name': user_info.get('last_name', ''),
            'groups': user_info.get('groups', []),
            'permissions': permissions,
            'department': user_info.get('department', ''),
            'iat': now,
            'exp': expiration,
            'iss': 'auth-portal',
            'aud': ['dashboard', 'cae', 'vnc']
        }

        token = jwt.encode(
            payload,
            Config.JWT_SECRET_KEY,
            algorithm=Config.JWT_ALGORITHM
        )

        return token

    @staticmethod
    def verify_token(token):
        """JWT 토큰 검증"""
        try:
            payload = jwt.decode(
                token,
                Config.JWT_SECRET_KEY,
                algorithms=[Config.JWT_ALGORITHM],
                options={
                    'verify_signature': True,
                    'verify_exp': True,
                    'verify_iat': True,
                    'require_exp': True,
                    'require_iat': True
                }
            )
            return payload, None
        except jwt.ExpiredSignatureError:
            return None, 'Token has expired'
        except jwt.InvalidTokenError as e:
            return None, f'Invalid token: {str(e)}'

    @staticmethod
    def decode_token_without_verification(token):
        """토큰 디코딩 (검증 없이 - 디버깅용)"""
        try:
            payload = jwt.decode(
                token,
                options={'verify_signature': False}
            )
            return payload
        except Exception as e:
            return None
```

#### Step 2.4: Redis 클라이언트 (redis_client.py)
```python
# redis_client.py
import redis
import json
from datetime import timedelta
from config import Config

class RedisClient:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._init_redis()
        return cls._instance

    def _init_redis(self):
        """Redis 연결 초기화"""
        self.client = redis.Redis(
            host=Config.REDIS_HOST,
            port=Config.REDIS_PORT,
            db=Config.REDIS_DB,
            password=Config.REDIS_PASSWORD if Config.REDIS_PASSWORD else None,
            decode_responses=True
        )

    def save_session(self, user_id, session_data, ttl_hours=None):
        """사용자 세션 저장"""
        key = f'session:{user_id}'
        ttl = ttl_hours or Config.JWT_EXPIRATION_HOURS

        self.client.setex(
            key,
            timedelta(hours=ttl),
            json.dumps(session_data)
        )

    def get_session(self, user_id):
        """사용자 세션 조회"""
        key = f'session:{user_id}'
        data = self.client.get(key)
        return json.loads(data) if data else None

    def delete_session(self, user_id):
        """사용자 세션 삭제"""
        key = f'session:{user_id}'
        self.client.delete(key)

    def session_exists(self, user_id):
        """세션 존재 여부 확인"""
        key = f'session:{user_id}'
        return self.client.exists(key) > 0

    def get_session_ttl(self, user_id):
        """세션 남은 시간 (초 단위)"""
        key = f'session:{user_id}'
        return self.client.ttl(key)
```

#### ✅ Day 3-4 완료 체크리스트
- [ ] config.py 작성 (환경 변수 로드, 권한 매핑)
- [ ] saml_handler.py 작성 (SAML 인증 처리)
- [ ] jwt_handler.py 작성 (JWT 생성/검증)
- [ ] redis_client.py 작성 (세션 관리)

---

### Day 5-7: Flask 애플리케이션 구현

#### Step 3.1: 메인 애플리케이션 (app.py)
```python
# app.py
from flask import Flask, request, jsonify, redirect, url_for
from flask_cors import CORS
from config import Config
from saml_handler import SAMLHandler
from jwt_handler import JWTHandler
from redis_client import RedisClient
import logging

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/auth_portal.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask 앱 초기화
app = Flask(__name__)
app.config.from_object(Config)

# CORS 설정
CORS(app, origins=Config.CORS_ORIGINS, supports_credentials=True)

# Redis 클라이언트
redis_client = RedisClient()

@app.route('/health', methods=['GET'])
def health_check():
    """헬스 체크 엔드포인트"""
    try:
        # Redis 연결 확인
        redis_client.client.ping()
        redis_status = 'ok'
    except Exception as e:
        redis_status = f'error: {str(e)}'

    return jsonify({
        'status': 'healthy',
        'service': 'auth-portal',
        'version': '1.0.0',
        'checks': {
            'redis': redis_status
        }
    }), 200

@app.route('/auth/saml/login', methods=['GET'])
def saml_login():
    """SAML SSO 로그인 시작"""
    try:
        auth = SAMLHandler.init_saml_auth(request)
        sso_url = auth.login()
        logger.info(f'SAML login initiated, redirecting to: {sso_url}')
        return redirect(sso_url)
    except Exception as e:
        logger.error(f'SAML login error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/auth/saml/acs', methods=['POST'])
def saml_acs():
    """SAML Assertion Consumer Service"""
    try:
        # SAML Response 처리
        user_info = SAMLHandler.process_saml_response(request)
        logger.info(f'SAML authentication successful for user: {user_info["username"]}')

        # JWT 토큰 생성
        token = JWTHandler.create_token(user_info)

        # Redis에 세션 저장
        session_data = {
            'username': user_info['username'],
            'email': user_info['email'],
            'groups': user_info['groups'],
            'login_time': datetime.utcnow().isoformat()
        }
        redis_client.save_session(user_info['username'], session_data)

        logger.info(f'JWT token created and session saved for: {user_info["username"]}')

        # Frontend ServiceMenu로 리다이렉트 (토큰 전달)
        frontend_url = Config.CORS_ORIGINS[0]  # http://localhost:4431
        return redirect(f'{frontend_url}/service-menu?token={token}')

    except Exception as e:
        logger.error(f'SAML ACS error: {str(e)}')
        frontend_url = Config.CORS_ORIGINS[0]
        return redirect(f'{frontend_url}/login?error={str(e)}')

@app.route('/auth/verify', methods=['POST'])
def verify_token():
    """JWT 토큰 검증"""
    try:
        # Authorization 헤더에서 토큰 추출
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No token provided'}), 401

        token = auth_header.split(' ')[1]

        # 토큰 검증
        payload, error = JWTHandler.verify_token(token)
        if error:
            logger.warning(f'Token verification failed: {error}')
            return jsonify({'error': error}), 401

        # Redis 세션 확인 (선택사항, 추가 보안)
        username = payload.get('sub')
        if not redis_client.session_exists(username):
            logger.warning(f'Session not found for user: {username}')
            return jsonify({'error': 'Session expired'}), 401

        logger.info(f'Token verified for user: {username}')
        return jsonify({
            'valid': True,
            'user': {
                'username': payload.get('sub'),
                'email': payload.get('email'),
                'name': payload.get('name'),
                'groups': payload.get('groups', []),
                'permissions': payload.get('permissions', [])
            }
        }), 200

    except Exception as e:
        logger.error(f'Token verification error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/auth/logout', methods=['POST'])
def logout():
    """로그아웃"""
    try:
        # Authorization 헤더에서 토큰 추출
        auth_header = request.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
            payload, _ = JWTHandler.verify_token(token)
            if payload:
                username = payload.get('sub')
                redis_client.delete_session(username)
                logger.info(f'User logged out: {username}')

        return jsonify({'message': 'Logged out successfully'}), 200
    except Exception as e:
        logger.error(f'Logout error: {str(e)}')
        return jsonify({'error': str(e)}), 500

@app.route('/auth/metadata', methods=['GET'])
def sp_metadata():
    """Service Provider 메타데이터"""
    try:
        auth = SAMLHandler.init_saml_auth(request)
        settings = auth.get_settings()
        metadata = settings.get_sp_metadata()
        errors = settings.validate_metadata(metadata)

        if errors:
            return jsonify({'errors': errors}), 500

        return metadata, 200, {'Content-Type': 'text/xml'}
    except Exception as e:
        logger.error(f'Metadata generation error: {str(e)}')
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    import os
    os.makedirs('logs', exist_ok=True)
    app.run(
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG
    )
```

#### Step 3.2: 애플리케이션 시작 스크립트
```bash
cat > start_auth_backend.sh << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"

# 가상 환경 활성화
source venv/bin/activate

# 로그 디렉토리 생성
mkdir -p logs

# 환경 변수 로드
export FLASK_APP=app.py
export FLASK_ENV=development

# 기존 프로세스 확인
if pgrep -f "flask run.*4430" > /dev/null; then
    echo "Auth Backend가 이미 실행 중입니다."
    exit 1
fi

# Flask 앱 시작
echo "Starting Auth Backend on port 4430..."
python app.py > logs/app.log 2>&1 &

PID=$!
echo $PID > logs/app.pid

sleep 2

if ps -p $PID > /dev/null; then
    echo "✓ Auth Backend started successfully (PID: $PID)"
    echo "  API URL: http://localhost:4430"
    echo "  Health Check: http://localhost:4430/health"
    echo "  SAML Login: http://localhost:4430/auth/saml/login"
else
    echo "✗ Failed to start Auth Backend"
    cat logs/app.log
    exit 1
fi
EOF

chmod +x start_auth_backend.sh
```

#### Step 3.3: 중지 스크립트
```bash
cat > stop_auth_backend.sh << 'EOF'
#!/bin/bash

PID_FILE="logs/app.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Stopping Auth Backend (PID: $PID)..."
        kill $PID
        rm "$PID_FILE"
        echo "✓ Auth Backend stopped"
    else
        echo "Auth Backend is not running (stale PID file)"
        rm "$PID_FILE"
    fi
else
    echo "Auth Backend is not running (no PID file)"
fi
EOF

chmod +x stop_auth_backend.sh
```

#### Step 3.4: 테스트
```bash
# Backend 시작
./start_auth_backend.sh

# Health Check
curl http://localhost:4430/health | jq

# SP 메타데이터 확인
curl http://localhost:4430/auth/metadata

# SAML 로그인 URL 테스트 (리다이렉트 확인)
curl -I http://localhost:4430/auth/saml/login
```

#### ✅ Day 5-7 완료 체크리스트
- [ ] app.py 메인 애플리케이션 작성
- [ ] SAML 로그인 엔드포인트 구현 (`/auth/saml/login`)
- [ ] ACS 엔드포인트 구현 (`/auth/saml/acs`)
- [ ] JWT 검증 엔드포인트 구현 (`/auth/verify`)
- [ ] 로그아웃 엔드포인트 구현
- [ ] 시작/중지 스크립트 작성
- [ ] Health Check 테스트 성공

---

## Week 2: Auth Frontend 개발

### Day 8-9: React 프로젝트 생성 및 기본 설정

#### 🎯 목표
Vite + React + TypeScript 프로젝트 생성 및 라우팅 설정

#### Step 4.1: 프로젝트 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

# Vite로 React + TypeScript 프로젝트 생성
npm create vite@latest auth_portal_4431 -- --template react-ts

cd auth_portal_4431

# 패키지 설치
npm install

# 추가 패키지 설치
npm install react-router-dom
npm install axios
npm install jwt-decode
npm install @types/jwt-decode --save-dev

# UI 라이브러리 (선택사항)
npm install @mui/material @emotion/react @emotion/styled
npm install @mui/icons-material
```

#### Step 4.2: 환경 변수 설정
```bash
cat > .env << 'EOF'
VITE_AUTH_BACKEND_URL=http://localhost:4430
VITE_SAML_LOGIN_URL=http://localhost:4430/auth/saml/login
VITE_DASHBOARD_URL=https://localhost/dashboard
VITE_CAE_URL=https://localhost/cae
EOF
```

#### Step 4.3: 디렉토리 구조 생성
```bash
mkdir -p src/{pages,components,utils,api,types,styles}
```

#### Step 4.4: TypeScript 타입 정의
```typescript
// src/types/auth.ts
export interface User {
  username: string;
  email: string;
  name: string;
  firstName: string;
  lastName: string;
  groups: string[];
  permissions: string[];
  department: string;
}

export interface JWTPayload {
  sub: string;
  email: string;
  name: string;
  first_name: string;
  last_name: string;
  groups: string[];
  permissions: string[];
  department: string;
  iat: number;
  exp: number;
  iss: string;
  aud: string[];
}

export interface Service {
  id: string;
  name: string;
  description: string;
  url: string;
  icon: string;
  requiredGroups: string[];
}
```

#### Step 4.5: JWT 유틸리티
```typescript
// src/utils/jwt.ts
import { jwtDecode } from 'jwt-decode';
import type { JWTPayload, User } from '../types/auth';

export const decodeToken = (token: string): JWTPayload | null => {
  try {
    return jwtDecode<JWTPayload>(token);
  } catch (error) {
    console.error('Failed to decode token:', error);
    return null;
  }
};

export const isTokenExpired = (token: string): boolean => {
  const payload = decodeToken(token);
  if (!payload) return true;

  const now = Math.floor(Date.now() / 1000);
  return payload.exp < now;
};

export const getTokenGroups = (token: string): string[] => {
  const payload = decodeToken(token);
  return payload?.groups || [];
};

export const getTokenPermissions = (token: string): string[] => {
  const payload = decodeToken(token);
  return payload?.permissions || [];
};

export const payloadToUser = (payload: JWTPayload): User => {
  return {
    username: payload.sub,
    email: payload.email,
    name: payload.name,
    firstName: payload.first_name,
    lastName: payload.last_name,
    groups: payload.groups,
    permissions: payload.permissions,
    department: payload.department
  };
};

export const saveToken = (token: string): void => {
  localStorage.setItem('jwt_token', token);
};

export const getToken = (): string | null => {
  return localStorage.getItem('jwt_token');
};

export const removeToken = (): void => {
  localStorage.removeItem('jwt_token');
};
```

#### ✅ Day 8-9 완료 체크리스트
- [ ] Vite React TypeScript 프로젝트 생성
- [ ] 필수 패키지 설치 (react-router-dom, axios, jwt-decode)
- [ ] 환경 변수 설정
- [ ] 디렉토리 구조 생성
- [ ] TypeScript 타입 정의
- [ ] JWT 유틸리티 함수 작성

---

### Day 10-12: 페이지 컴포넌트 구현

#### Step 5.1: Login 페이지
```typescript
// src/pages/Login.tsx
import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Box, Button, Typography, Container, Alert } from '@mui/material';
import LoginIcon from '@mui/icons-material/Login';

const Login = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const error = searchParams.get('error');

  useEffect(() => {
    // 이미 토큰이 있으면 ServiceMenu로 리다이렉트
    const token = localStorage.getItem('jwt_token');
    if (token) {
      navigate('/service-menu');
    }
  }, [navigate]);

  const handleSSOLogin = () => {
    // SAML SSO 로그인 URL로 리다이렉트
    window.location.href = import.meta.env.VITE_SAML_LOGIN_URL;
  };

  return (
    <Container maxWidth="sm">
      <Box
        sx={{
          marginTop: 8,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
        }}
      >
        <Typography component="h1" variant="h3" gutterBottom>
          HPC Dashboard
        </Typography>
        <Typography variant="h6" color="text.secondary" gutterBottom>
          통합 인증 포털
        </Typography>

        {error && (
          <Alert severity="error" sx={{ mt: 2, width: '100%' }}>
            로그인 실패: {error}
          </Alert>
        )}

        <Box sx={{ mt: 4, width: '100%' }}>
          <Button
            fullWidth
            variant="contained"
            size="large"
            startIcon={<LoginIcon />}
            onClick={handleSSOLogin}
            sx={{ py: 1.5 }}
          >
            SSO 로그인
          </Button>
        </Box>

        <Typography variant="body2" color="text.secondary" sx={{ mt: 3 }}>
          조직의 계정으로 로그인하세요
        </Typography>
      </Box>
    </Container>
  );
};

export default Login;
```

#### Step 5.2: ServiceMenu 페이지
```typescript
// src/pages/ServiceMenu.tsx
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Container,
  Grid,
  Card,
  CardContent,
  CardActions,
  Button,
  Typography,
  Box,
  Chip,
  AppBar,
  Toolbar,
  IconButton
} from '@mui/material';
import DashboardIcon from '@mui/icons-material/Dashboard';
import PrecisionManufacturingIcon from '@mui/icons-material/PrecisionManufacturing';
import DesktopWindowsIcon from '@mui/icons-material/DesktopWindows';
import LogoutIcon from '@mui/icons-material/Logout';
import { decodeToken, saveToken, getToken, removeToken, payloadToUser } from '../utils/jwt';
import type { User, Service } from '../types/auth';

const ServiceMenu = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    // URL 파라미터에서 토큰 추출
    const tokenFromUrl = searchParams.get('token');

    if (tokenFromUrl) {
      // 토큰 저장
      saveToken(tokenFromUrl);

      // URL에서 토큰 제거 (브라우저 히스토리에 남지 않도록)
      window.history.replaceState({}, '', '/service-menu');

      // 토큰 디코딩
      const payload = decodeToken(tokenFromUrl);
      if (payload) {
        setUser(payloadToUser(payload));
      }
    } else {
      // localStorage에서 토큰 가져오기
      const token = getToken();
      if (token) {
        const payload = decodeToken(token);
        if (payload) {
          setUser(payloadToUser(payload));
        } else {
          // 유효하지 않은 토큰
          navigate('/');
        }
      } else {
        // 토큰 없음
        navigate('/');
      }
    }
  }, [searchParams, navigate]);

  const handleLogout = () => {
    removeToken();
    navigate('/');
  };

  const handleServiceClick = (service: Service) => {
    const token = getToken();
    if (token) {
      // 서비스 URL에 토큰 전달
      window.location.href = `${service.url}?token=${token}`;
    }
  };

  // 서비스 목록 정의
  const allServices: Service[] = [
    {
      id: 'dashboard',
      name: '관리 대시보드',
      description: 'Slurm 클러스터 관리 및 Job 제출',
      url: import.meta.env.VITE_DASHBOARD_URL,
      icon: 'dashboard',
      requiredGroups: ['HPC-Admins', 'HPC-Users']
    },
    {
      id: 'vnc',
      name: 'VNC 시각화',
      description: 'GPU 원격 데스크톱 세션',
      url: `${import.meta.env.VITE_DASHBOARD_URL}/vnc`,
      icon: 'desktop',
      requiredGroups: ['HPC-Admins', 'HPC-Users', 'GPU-Users']
    },
    {
      id: 'cae',
      name: 'CAE 자동화',
      description: '워크플로우 기반 자동화 시스템',
      url: import.meta.env.VITE_CAE_URL,
      icon: 'automation',
      requiredGroups: ['HPC-Admins', 'Automation-Users']
    }
  ];

  // 사용자 그룹에 따라 접근 가능한 서비스 필터링
  const availableServices = allServices.filter(service =>
    user?.groups.some(group => service.requiredGroups.includes(group))
  );

  const getServiceIcon = (icon: string) => {
    switch (icon) {
      case 'dashboard':
        return <DashboardIcon sx={{ fontSize: 60 }} />;
      case 'desktop':
        return <DesktopWindowsIcon sx={{ fontSize: 60 }} />;
      case 'automation':
        return <PrecisionManufacturingIcon sx={{ fontSize: 60 }} />;
      default:
        return <DashboardIcon sx={{ fontSize: 60 }} />;
    }
  };

  if (!user) {
    return <div>Loading...</div>;
  }

  return (
    <>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            서비스 선택
          </Typography>
          <Typography variant="body1" sx={{ mr: 2 }}>
            {user.name} ({user.email})
          </Typography>
          <IconButton color="inherit" onClick={handleLogout}>
            <LogoutIcon />
          </IconButton>
        </Toolbar>
      </AppBar>

      <Container sx={{ mt: 4 }}>
        <Box sx={{ mb: 3 }}>
          <Typography variant="h5" gutterBottom>
            안녕하세요, {user.firstName}님
          </Typography>
          <Box sx={{ display: 'flex', gap: 1, mt: 1 }}>
            {user.groups.map(group => (
              <Chip key={group} label={group} color="primary" size="small" />
            ))}
          </Box>
        </Box>

        <Typography variant="h6" gutterBottom sx={{ mt: 4 }}>
          이용 가능한 서비스
        </Typography>

        <Grid container spacing={3} sx={{ mt: 1 }}>
          {availableServices.map(service => (
            <Grid item xs={12} sm={6} md={4} key={service.id}>
              <Card>
                <CardContent>
                  <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}>
                    {getServiceIcon(service.icon)}
                  </Box>
                  <Typography variant="h6" component="div" gutterBottom>
                    {service.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {service.description}
                  </Typography>
                </CardContent>
                <CardActions>
                  <Button
                    fullWidth
                    variant="contained"
                    onClick={() => handleServiceClick(service)}
                  >
                    시작하기
                  </Button>
                </CardActions>
              </Card>
            </Grid>
          ))}
        </Grid>

        {availableServices.length === 0 && (
          <Typography variant="body1" color="text.secondary" sx={{ mt: 2 }}>
            이용 가능한 서비스가 없습니다. 관리자에게 문의하세요.
          </Typography>
        )}
      </Container>
    </>
  );
};

export default ServiceMenu;
```

#### Step 5.3: App.tsx (라우팅 설정)
```typescript
// src/App.tsx
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme, CssBaseline } from '@mui/material';
import Login from './pages/Login';
import ServiceMenu from './pages/ServiceMenu';

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1976d2',
    },
    secondary: {
      main: '#dc004e',
    },
  },
});

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Router>
        <Routes>
          <Route path="/" element={<Login />} />
          <Route path="/service-menu" element={<ServiceMenu />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Router>
    </ThemeProvider>
  );
}

export default App;
```

#### Step 5.4: 개발 서버 설정
```typescript
// vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 4431,
    host: '0.0.0.0',
    proxy: {
      '/auth': {
        target: 'http://localhost:4430',
        changeOrigin: true
      }
    }
  }
})
```

#### Step 5.5: 시작 스크립트
```bash
cat > start_auth_frontend.sh << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"

# 기존 프로세스 확인
if pgrep -f "vite.*4431" > /dev/null; then
    echo "Auth Frontend가 이미 실행 중입니다."
    exit 1
fi

# Vite 개발 서버 시작
echo "Starting Auth Frontend on port 4431..."
npm run dev > logs/frontend.log 2>&1 &

PID=$!
mkdir -p logs
echo $PID > logs/frontend.pid

sleep 3

if ps -p $PID > /dev/null; then
    echo "✓ Auth Frontend started successfully (PID: $PID)"
    echo "  URL: http://localhost:4431"
else
    echo "✗ Failed to start Auth Frontend"
    cat logs/frontend.log
    exit 1
fi
EOF

chmod +x start_auth_frontend.sh
```

#### ✅ Day 10-12 완료 체크리스트
- [ ] Login 페이지 구현
- [ ] ServiceMenu 페이지 구현
- [ ] 라우팅 설정 (App.tsx)
- [ ] Vite 설정 (프록시, 포트)
- [ ] 시작 스크립트 작성
- [ ] 개발 서버 테스트

---

## Week 3: 통합 및 테스트

### Day 13-14: 통합 테스트

#### 🎯 목표
전체 인증 플로우 통합 테스트 및 검증

#### Step 6.1: 통합 테스트 스크립트
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

cat > test_auth_flow.sh << 'EOF'
#!/bin/bash

echo "=== Auth Portal 통합 테스트 ==="
echo

# 1. SAML-IdP 실행 확인
echo "1. SAML-IdP 상태 확인..."
if curl -sf http://localhost:7000/metadata > /dev/null; then
    echo "✓ SAML-IdP 실행 중"
else
    echo "✗ SAML-IdP가 실행되지 않음"
    echo "  실행: cd saml_idp_7000 && ./start_idp.sh"
    exit 1
fi

# 2. Auth Backend 실행 확인
echo "2. Auth Backend 상태 확인..."
if curl -sf http://localhost:4430/health > /dev/null; then
    echo "✓ Auth Backend 실행 중"
    curl -s http://localhost:4430/health | jq
else
    echo "✗ Auth Backend가 실행되지 않음"
    echo "  실행: cd auth_portal_4430 && ./start_auth_backend.sh"
    exit 1
fi

# 3. Auth Frontend 실행 확인
echo "3. Auth Frontend 상태 확인..."
if curl -sf http://localhost:4431 > /dev/null; then
    echo "✓ Auth Frontend 실행 중"
else
    echo "✗ Auth Frontend가 실행되지 않음"
    echo "  실행: cd auth_portal_4431 && ./start_auth_frontend.sh"
    exit 1
fi

# 4. Nginx HTTPS 확인
echo "4. Nginx HTTPS 확인..."
if curl -k -sf https://localhost > /dev/null; then
    echo "✓ Nginx HTTPS 접속 가능"
else
    echo "✗ Nginx HTTPS 접속 불가"
    exit 1
fi

# 5. SAML 로그인 URL 확인
echo "5. SAML 로그인 URL 확인..."
REDIRECT=$(curl -s -o /dev/null -w "%{redirect_url}" http://localhost:4430/auth/saml/login)
if [[ $REDIRECT == *"localhost:7000"* ]]; then
    echo "✓ SAML 로그인 리다이렉트 정상"
    echo "  → $REDIRECT"
else
    echo "✗ SAML 로그인 리다이렉트 실패"
fi

echo
echo "=== 수동 테스트 절차 ==="
echo "1. 브라우저에서 http://localhost:4431 접속"
echo "2. 'SSO 로그인' 버튼 클릭"
echo "3. SAML-IdP 로그인 페이지에서 다음 계정 사용:"
echo "   - admin@hpc.local / admin123"
echo "   - user01@hpc.local / password123"
echo "4. 로그인 성공 후 ServiceMenu 페이지 확인"
echo "5. 그룹별 서비스 목록 표시 확인"
echo "6. 브라우저 개발자 도구에서 localStorage의 jwt_token 확인"
echo
echo "JWT 디코딩: https://jwt.io"
EOF

chmod +x test_auth_flow.sh
```

#### Step 6.2: 실행 및 검증
```bash
# 모든 서비스 시작 (아직 실행 중이 아닌 경우)
cd saml_idp_7000 && ./start_idp.sh && cd ..
cd auth_portal_4430 && ./start_auth_backend.sh && cd ..
cd auth_portal_4431 && ./start_auth_frontend.sh && cd ..

# 통합 테스트 실행
./test_auth_flow.sh

# 브라우저 테스트
firefox http://localhost:4431 &
```

#### ✅ Day 13-14 완료 체크리스트
- [ ] 통합 테스트 스크립트 작성
- [ ] SAML SSO 로그인 테스트 성공
- [ ] JWT 토큰 발급 확인
- [ ] ServiceMenu 그룹별 필터링 확인
- [ ] Redis 세션 저장 확인

---

### Day 15: 문서화 및 Phase 1 완료

#### Step 7.1: API 문서 작성
```markdown
# Auth Portal API Documentation

## 엔드포인트

### 1. Health Check
- **URL**: `GET /health`
- **설명**: 서비스 상태 확인
- **응답**:
  ```json
  {
    "status": "healthy",
    "service": "auth-portal",
    "version": "1.0.0",
    "checks": {
      "redis": "ok"
    }
  }
  ```

### 2. SAML SSO 로그인
- **URL**: `GET /auth/saml/login`
- **설명**: SAML SSO 로그인 시작
- **응답**: IdP로 리다이렉트

### 3. SAML ACS
- **URL**: `POST /auth/saml/acs`
- **설명**: SAML Assertion Consumer Service
- **요청**: SAML Response (POST)
- **응답**: ServiceMenu로 리다이렉트 + JWT 토큰

### 4. JWT 검증
- **URL**: `POST /auth/verify`
- **헤더**: `Authorization: Bearer <token>`
- **응답**:
  ```json
  {
    "valid": true,
    "user": {
      "username": "user01",
      "email": "user01@hpc.local",
      "name": "테스트 사용자1",
      "groups": ["HPC-Users", "GPU-Users"],
      "permissions": ["dashboard.view", "jobs.submit", ...]
    }
  }
  ```

### 5. 로그아웃
- **URL**: `POST /auth/logout`
- **헤더**: `Authorization: Bearer <token>`
- **응답**: `{"message": "Logged out successfully"}`
```

#### Step 7.2: Phase 1 완료 보고서
```bash
cat > Phase1_Completion_Report.md << 'EOF'
# Phase 1 완료 보고서

**완료일**: $(date +%Y-%m-%d)
**소요 시간**: 2-3주

## 완료된 작업

### Week 1: Auth Backend
- [x] Flask 프로젝트 구조 생성
- [x] SAML 설정 및 SP 인증서 생성
- [x] SAML 핸들러 구현
- [x] JWT 토큰 발급/검증 구현
- [x] Redis 세션 관리 구현
- [x] Flask API 엔드포인트 구현

### Week 2: Auth Frontend
- [x] React + TypeScript 프로젝트 생성
- [x] Login 페이지 구현
- [x] ServiceMenu 페이지 구현
- [x] JWT 유틸리티 함수
- [x] 그룹 기반 서비스 필터링

### Week 3: 통합 및 테스트
- [x] SAML SSO 플로우 통합 테스트
- [x] JWT 토큰 검증 테스트
- [x] Redis 세션 저장 확인
- [x] API 문서 작성

## 검증 결과
- ✓ SAML SSO 로그인 성공
- ✓ JWT 토큰 발급 및 검증 정상
- ✓ ServiceMenu 그룹별 필터링 정상
- ✓ Redis 세션 저장/조회 정상

## 다음 단계: Phase 2
- 기존 서비스(backend_5010, frontend_3010)에 JWT 인증 추가
- JWT 미들웨어 구현
- API 권한 검증
EOF

sed -i "s/\$(date +%Y-%m-%d)/$(date +%Y-%m-%d)/" Phase1_Completion_Report.md
```

---

## 검증 체크리스트

### 전체 Phase 1 검증

#### Backend (8개)
- [ ] Flask 앱 실행 (`http://localhost:4430/health`)
- [ ] SAML 로그인 URL (`/auth/saml/login`)
- [ ] SAML ACS 처리 (`/auth/saml/acs`)
- [ ] JWT 토큰 생성
- [ ] JWT 토큰 검증 (`/auth/verify`)
- [ ] Redis 세션 저장
- [ ] 로그아웃 (`/auth/logout`)
- [ ] SP 메타데이터 (`/auth/metadata`)

#### Frontend (6개)
- [ ] Login 페이지 렌더링
- [ ] SSO 로그인 버튼 동작
- [ ] ServiceMenu 페이지 렌더링
- [ ] JWT 토큰 localStorage 저장
- [ ] 그룹별 서비스 필터링
- [ ] 서비스 선택 시 토큰 전달

#### 통합 (5개)
- [ ] 전체 SSO 플로우 성공
- [ ] JWT 페이로드 검증 (그룹, 권한)
- [ ] Redis 세션 TTL 확인
- [ ] 로그아웃 후 세션 삭제
- [ ] Nginx HTTPS 프록시 동작

---

## 트러블슈팅

### 문제: SAML 응답 검증 실패
```bash
# SAML 설정 확인
cat auth_portal_4430/saml/settings.json | jq

# IdP 메타데이터 재다운로드
curl http://localhost:7000/metadata > auth_portal_4430/saml/metadata/idp_metadata.xml

# Backend 재시작
cd auth_portal_4430
./stop_auth_backend.sh
./start_auth_backend.sh
```

### 문제: JWT 토큰 검증 실패
```bash
# .env 파일의 JWT_SECRET_KEY 확인
grep JWT_SECRET_KEY auth_portal_4430/.env

# 토큰 디코딩 (검증 없이)
python3 << EOF
import jwt
token = "your_token_here"
payload = jwt.decode(token, options={"verify_signature": False})
print(payload)
EOF
```

### 문제: ServiceMenu에 서비스가 표시되지 않음
```bash
# JWT 페이로드의 groups 확인
# 브라우저 개발자 도구 Console:
localStorage.getItem('jwt_token')

# jwt.io에서 디코딩하여 groups 필드 확인
```

---

**Phase 1 완료!** 🎉

다음: **Phase 2 - 기존 서비스 통합** (backend_5010, frontend_3010에 JWT 추가)
