# Phase 4: Security & Infrastructure - v4.4.0

## Overview
기존 인증 시스템과 WebSocket 인프라를 활용한 보안 및 인프라 개선

**Date:** 2025-11-05
**Version:** 4.4.0 (Phase 4)
**Previous:** v4.3.2 (Phase 3 완료)

---

## 🔒 핵심 원칙 준수 (CRITICAL)

### 1. 기존 시스템 보호
- ✅ **JWT 인증 시스템**: 이미 잘 작동하는 시스템 유지
  - `jwt_middleware.py` - 검증됨
  - `AuthContext.tsx` - 정상 작동
  - `api.ts` - JWT 토큰 관리 완료
- ✅ **WebSocket 서버**: 5011 포트에서 정상 운영 중
  - `websocket_server.py` - broadcast_message() 구현됨
  - Storage updates, 실시간 데이터 전송 검증
- ⚠️ **절대 수정 금지**: 위 파일들을 직접 수정하지 않음

### 2. 점진적 개선
- 새로운 기능은 **추가**로만 구현
- 기존 API 엔드포인트는 **그대로 유지**
- 새 엔드포인트는 `/api/v2/` prefix 사용

### 3. 독립적 구현
- 기존 기능에 의존하지 않음
- 실패 시 기존 시스템은 영향 없음
- 롤백 가능한 구조

---

## 📊 기존 시스템 분석 결과

### JWT 인증 시스템 (✅ 완료)

**Backend (backend_5010/middleware/jwt_middleware.py):**
```python
# 이미 구현된 데코레이터들:
@jwt_required              # JWT 토큰 검증
@permission_required()     # 권한 검증
@group_required()          # 그룹 검증
@optional_jwt              # 선택적 JWT

# JWT 구성:
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret')
JWT_ALGORITHM = 'HS256'

# g.user 구조:
{
  'username': payload.get('sub'),
  'email': payload.get('email'),
  'groups': payload.get('groups', []),
  'permissions': payload.get('permissions', [])
}
```

**Frontend (src/contexts/AuthContext.tsx, src/utils/api.ts):**
```typescript
// localStorage에 'jwt_token' 저장
// API 요청 시 Authorization: Bearer <token> 헤더 자동 추가
// 토큰 만료 시 자동 로그아웃 (매 1분 체크)

interface UserInfo {
  username: string;
  email?: string;
  groups: string[];
  permissions?: string[];
  exp?: number;
}
```

**사용 예시 (이미 적용됨):**
```python
# backend_5010/app.py
@app.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def submit_job():
    user = g.user  # JWT에서 추출한 사용자 정보
    ...
```

### WebSocket 시스템 (✅ 완료)

**Backend (backend_5010/websocket_server.py):**
```python
# Port 5011에서 실행
# aiohttp 기반 WebSocket 서버

# 구현된 기능:
- connected_clients: Set[WebSocketResponse]  # 연결된 클라이언트 추적
- websocket_handler(request)                 # 연결 핸들러
- handle_client_message(ws, data)            # 메시지 처리
- broadcast_message(type, data)              # 브로드캐스트 (중요!)
- broadcast_updates()                        # 주기적 업데이트

# 메시지 형식:
{
  'type': 'upload_progress' | 'job_update' | 'periodic_update',
  'data': { ... },
  'timestamp': '2025-11-05T...'
}
```

**이미 사용 중:**
- File Upload API에서 `broadcast_message('upload_progress', {...})` 호출
- Storage updates 실시간 전송

**Frontend WebSocket 연동 예시 (useUploadProgress.ts):**
```typescript
const ws = new WebSocket('ws://localhost:5011/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'upload_progress') {
    // Handle progress update
  }
};
```

### SSO/Auth Portal (✅ 운영 중)

**Auth Portal (kooCAEWebServer_5000):**
- Port 4431에서 HTTPS로 운영
- LDAP/AD 연동
- JWT 토큰 발급
- 사용자 그룹 관리

**로그인 플로우:**
1. 사용자 → Auth Portal (4431) 로그인
2. Auth Portal → JWT 토큰 발급
3. Frontend → localStorage에 jwt_token 저장
4. 이후 모든 API 요청에 JWT 헤더 포함

---

## 🚀 Phase 4 구현 계획

### 원칙: **"기존 것은 건드리지 말고, 새로운 것만 추가"**

### 4.1 File Upload API 보안 강화 ✨

**목표:** 파일 업로드 API에 JWT 인증 및 사용자별 격리 추가

#### 현재 상태 분석
```python
# backend_5010/file_upload_api.py
# 현재: JWT 인증 없음
@file_upload_bp.route('/api/v2/files/upload/init', methods=['POST'])
def init_upload():
    data = request.json
    user_id = data.get('user_id')  # Frontend에서 직접 전달 (보안 취약!)
    ...
```

#### 개선 방안 (추가만)

**Step 1: JWT 인증 추가**
```python
# backend_5010/file_upload_api.py
from middleware.jwt_middleware import jwt_required, permission_required

# BEFORE (기존 - 유지)
@file_upload_bp.route('/api/v2/files/upload/init', methods=['POST'])
def init_upload():
    ...

# AFTER (새로 추가)
@file_upload_bp.route('/api/v2/files/upload/init', methods=['POST'])
@jwt_required                      # JWT 검증
@permission_required('dashboard')  # 권한 검증
def init_upload():
    # user_id를 JWT에서 추출 (Frontend 입력 무시)
    user = g.user
    user_id = user['username']  # JWT에서 가져옴 (안전!)

    data = request.json
    # data.get('user_id') 무시 - JWT가 진실의 원천

    # 나머지 로직은 동일
    ...
```

**Step 2: 사용자별 파일 격리**
```python
# 파일 저장 경로 변경
# BEFORE: /shared/uploads/jobs/{job_id}/
# AFTER:  /shared/uploads/users/{username}/jobs/{job_id}/

def get_user_upload_dir(username: str, job_id: str) -> str:
    """
    사용자별 업로드 디렉토리 생성
    각 사용자는 자신의 디렉토리에만 접근 가능
    """
    user_dir = os.path.join(UPLOAD_BASE_DIR, 'users', username)
    job_dir = os.path.join(user_dir, 'jobs', job_id)

    # 디렉토리 생성 (권한: 700)
    os.makedirs(job_dir, mode=0o700, exist_ok=True)

    # 소유권 변경 (해당 사용자로)
    # os.chown(job_dir, uid, gid)  # Optional

    return job_dir
```

**Step 3: 파일 접근 권한 검증**
```python
@file_upload_bp.route('/api/v2/files/uploads/<upload_id>', methods=['GET'])
@jwt_required
def get_upload(upload_id: str):
    user = g.user
    username = user['username']

    # 파일 조회
    upload = get_upload_from_db(upload_id)

    # 권한 검증: 본인 파일만 조회 가능 (관리자 예외)
    if upload['user_id'] != username and not is_admin(user):
        return jsonify({'error': 'Forbidden'}), 403

    return jsonify(upload), 200
```

#### 변경 파일
- ✏️ `backend_5010/file_upload_api.py` - JWT 데코레이터 추가
- 📝 Migration 불필요 (DB 스키마 변경 없음)

#### 테스트 체크리스트
- [ ] JWT 없이 업로드 시도 → 401 Unauthorized
- [ ] 유효하지 않은 JWT → 401 Unauthorized
- [ ] 타 사용자 파일 조회 시도 → 403 Forbidden
- [ ] 관리자는 모든 파일 조회 가능
- [ ] 파일 저장 경로 검증 (`/shared/uploads/users/{username}/`)

---

### 4.2 Rate Limiting (선택적) 🚦

**목표:** API 남용 방지 (DDoS, 무차별 대입 공격)

#### 구현 방안

**Option 1: Flask-Limiter 사용 (권장)**
```python
# backend_5010/app.py (추가만)
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["1000 per day", "100 per hour"],
    storage_uri="redis://localhost:6379"  # Redis 사용
)

# 파일 업로드: 분당 10회
@limiter.limit("10 per minute")
@file_upload_bp.route('/api/v2/files/upload/chunk', methods=['POST'])
@jwt_required
def upload_chunk():
    ...

# Job Submit: 분당 5회
@limiter.limit("5 per minute")
@app.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required
def submit_job():
    ...
```

**Option 2: 수동 Rate Limiting (Redis 없는 경우)**
```python
# backend_5010/utils/rate_limiter.py (신규 파일)
from functools import wraps
from flask import request, jsonify, g
from datetime import datetime, timedelta
from collections import defaultdict
import threading

# 메모리 기반 Rate Limiter
request_counts = defaultdict(list)
lock = threading.Lock()

def rate_limit(max_requests: int, window_seconds: int):
    """
    메모리 기반 Rate Limiting 데코레이터

    Args:
        max_requests: 허용 요청 수
        window_seconds: 시간 윈도우 (초)
    """
    def decorator(f):
        @wraps(f)
        def wrapped(*args, **kwargs):
            # 사용자 식별 (JWT username 또는 IP)
            user = g.get('user')
            key = user['username'] if user else request.remote_addr

            now = datetime.now()
            window_start = now - timedelta(seconds=window_seconds)

            with lock:
                # 오래된 요청 제거
                request_counts[key] = [
                    req_time for req_time in request_counts[key]
                    if req_time > window_start
                ]

                # Rate limit 체크
                if len(request_counts[key]) >= max_requests:
                    return jsonify({
                        'error': 'Rate limit exceeded',
                        'message': f'Maximum {max_requests} requests per {window_seconds}s'
                    }), 429

                # 요청 기록
                request_counts[key].append(now)

            return f(*args, **kwargs)
        return wrapped
    return decorator

# 사용 예:
from utils.rate_limiter import rate_limit

@rate_limit(max_requests=10, window_seconds=60)  # 분당 10회
@file_upload_bp.route('/api/v2/files/upload/chunk', methods=['POST'])
@jwt_required
def upload_chunk():
    ...
```

#### 변경 파일
- 📁 `backend_5010/utils/rate_limiter.py` (신규, Option 2)
- ✏️ `backend_5010/file_upload_api.py` - Rate limiter 적용
- ✏️ `backend_5010/app.py` - Rate limiter 적용

#### 우선순위
- 🟡 **Medium** (Phase 5로 연기 가능)
- Redis 설치 필요 시 부담
- Option 2 (메모리 기반)는 간단하지만 다중 프로세스 환경에서 제한적

---

### 4.3 파일 업로드 보안 검증 강화 🛡️

**목표:** 악성 파일 업로드 방지

#### 구현 방안

**Step 1: 파일 타입 검증 강화**
```python
# backend_5010/file_classifier.py (기존 파일 수정)
import magic  # python-magic

def validate_file_security(file_path: str, declared_type: str) -> dict:
    """
    파일 보안 검증

    Returns:
        {
            'safe': bool,
            'warnings': list,
            'detected_type': str
        }
    """
    warnings = []

    # 1. Magic Number 검증 (실제 파일 타입)
    mime = magic.from_file(file_path, mime=True)
    detected_extension = get_extension_from_mime(mime)

    # 2. 확장자 vs 실제 타입 비교
    file_ext = os.path.splitext(file_path)[1].lower()
    if file_ext != detected_extension:
        warnings.append(
            f"Extension mismatch: {file_ext} != {detected_extension}"
        )

    # 3. 실행 파일 차단
    dangerous_mimes = [
        'application/x-executable',
        'application/x-sharedlib',
        'application/x-dosexec'
    ]
    if mime in dangerous_mimes:
        return {
            'safe': False,
            'warnings': ['Executable files are not allowed'],
            'detected_type': mime
        }

    # 4. 파일 크기 검증 (이미 구현됨)

    # 5. 압축 파일 내부 검사 (선택적)
    if mime in ['application/zip', 'application/x-tar', 'application/gzip']:
        # ZIP bomb 검증
        if is_zip_bomb(file_path):
            return {
                'safe': False,
                'warnings': ['Potential zip bomb detected'],
                'detected_type': mime
            }

    return {
        'safe': True,
        'warnings': warnings,
        'detected_type': mime
    }
```

**Step 2: 업로드 중 보안 검증 추가**
```python
# backend_5010/file_upload_api.py
@file_upload_bp.route('/api/v2/files/upload/complete', methods=['POST'])
@jwt_required
def complete_upload():
    ...
    # 조립 완료 후
    final_path = assemble_chunks(upload_id, ...)

    # 보안 검증 추가
    from file_classifier import validate_file_security
    security_check = validate_file_security(final_path, file_type)

    if not security_check['safe']:
        # 파일 삭제
        os.remove(final_path)
        return jsonify({
            'error': 'Security validation failed',
            'warnings': security_check['warnings']
        }), 400

    # 검증 통과 → 완료 처리
    ...
```

#### 변경 파일
- ✏️ `backend_5010/file_classifier.py` - validate_file_security() 추가
- ✏️ `backend_5010/file_upload_api.py` - 보안 검증 추가
- 📦 `backend_5010/requirements.txt` - python-magic 추가

#### 테스트 체크리스트
- [ ] .exe 파일 업로드 시도 → 차단
- [ ] .txt.exe (확장자 위장) → 차단
- [ ] ZIP bomb → 차단
- [ ] 정상 파일 → 통과

---

### 4.4 WebSocket JWT 인증 (선택적) 🔐

**목표:** WebSocket 연결도 JWT로 보호

#### 현재 상태
```python
# backend_5010/websocket_server.py
# 현재: 인증 없이 모든 클라이언트 연결 허용
async def websocket_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    connected_clients.add(ws)  # 무조건 추가
    ...
```

#### 개선 방안 (조심스럽게)

**Option 1: Query Parameter로 JWT 전달 (간단)**
```python
# backend_5010/websocket_server.py
import jwt
from urllib.parse import parse_qs

async def websocket_handler(request):
    # JWT 검증
    try:
        # Query string에서 토큰 추출
        # ws://localhost:5011/ws?token=<jwt_token>
        query_string = request.rel_url.query_string
        params = parse_qs(query_string)
        token = params.get('token', [None])[0]

        if not token:
            return web.Response(status=401, text='Unauthorized')

        # JWT 검증
        JWT_SECRET = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret')
        payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])

        # 사용자 정보 저장
        username = payload.get('sub')

    except jwt.InvalidTokenError:
        return web.Response(status=401, text='Invalid token')

    # WebSocket 연결 수립
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    # 사용자 정보와 함께 저장
    ws.username = username  # 커스텀 속성
    connected_clients.add(ws)

    print(f"User {username} connected via WebSocket")
    ...
```

**Frontend 수정:**
```typescript
// src/hooks/useUploadProgress.ts
const token = localStorage.getItem('jwt_token');
const ws = new WebSocket(`ws://localhost:5011/ws?token=${token}`);
```

**Option 2: WebSocket 인증 생략 (현재 유지)**
- WebSocket은 읽기 전용 (브로드캐스트만)
- 민감 정보 전송 안 함
- 인증 없이 운영해도 큰 위험 없음

#### 우선순위
- 🟢 **Low** (Phase 5로 연기)
- 현재 WebSocket은 안전 (브로드캐스트 전용)
- 인증 추가 시 기존 클라이언트 호환성 문제

---

### 4.5 HTTPS 설정 (Infrastructure) 🔒

**목표:** 프로덕션 환경에서 HTTPS 강제

#### 구현 방안

**Option 1: Nginx Reverse Proxy (권장)**
```nginx
# /etc/nginx/sites-available/dashboard
server {
    listen 80;
    server_name dashboard.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name dashboard.example.com;

    ssl_certificate /etc/letsencrypt/live/dashboard.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dashboard.example.com/privkey.pem;

    # Frontend (정적 파일)
    location / {
        root /home/koopark/claude/.../dashboard/frontend_3010/dist;
        try_files $uri $uri/ /index.html;
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:5010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket
    location /ws {
        proxy_pass http://localhost:5011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Option 2: Flask SSL (개발용만)**
```python
# backend_5010/app.py
if __name__ == '__main__':
    # SSL context (개발용)
    context = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    context.load_cert_chain('cert.pem', 'key.pem')

    app.run(
        host='0.0.0.0',
        port=5010,
        ssl_context=context
    )
```

#### 변경 파일
- 📁 `/etc/nginx/sites-available/dashboard` (신규)
- 🔧 Let's Encrypt 인증서 설정

#### 우선순위
- 🟡 **Medium** (프로덕션 배포 전 필수)
- 개발 환경에서는 HTTP 유지 가능

---

## 📋 Phase 4 구현 우선순위

### 🔴 High Priority (필수)
1. **File Upload API JWT 인증** (4.1)
   - 현재 가장 취약한 부분
   - 누구나 파일 업로드 가능
   - 구현 간단 (데코레이터만 추가)

2. **파일 보안 검증** (4.3)
   - 악성 파일 업로드 방지
   - python-magic 설치 필요

### 🟡 Medium Priority (권장)
3. **HTTPS 설정** (4.5)
   - 프로덕션 배포 전 설정
   - Nginx 설정 필요

4. **Rate Limiting** (4.2)
   - API 남용 방지
   - 메모리 기반으로 간단히 구현 가능

### 🟢 Low Priority (선택적)
5. **WebSocket JWT 인증** (4.4)
   - 현재도 안전함
   - Phase 5로 연기 가능

---

## 🛠️ 구현 순서 (단계별)

### Step 1: File Upload API JWT 인증 (1-2시간)
1. `file_upload_api.py` 읽기
2. `@jwt_required`, `@permission_required` 데코레이터 추가
3. `user_id` = `g.user['username']`로 변경
4. 테스트 (Postman or curl)

### Step 2: 파일 보안 검증 (2-3시간)
1. `python-magic` 설치
2. `file_classifier.py`에 `validate_file_security()` 추가
3. `complete_upload()`에 보안 검증 추가
4. 테스트 (악성 파일 업로드 시도)

### Step 3: 빌드 & 테스트 (1시간)
1. Backend 재시작
2. Frontend 빌드 (변경 없음)
3. End-to-End 테스트
4. 문서화

### Step 4: Rate Limiting (선택, 2-3시간)
1. `utils/rate_limiter.py` 생성
2. 주요 API에 적용
3. 테스트

### Step 5: HTTPS (선택, 프로덕션 배포 시)
1. Let's Encrypt 인증서 발급
2. Nginx 설정
3. 리다이렉트 테스트

---

## 📊 예상 소요 시간

| 작업 | 우선순위 | 예상 시간 |
|------|---------|---------|
| JWT 인증 추가 | 🔴 High | 1-2시간 |
| 파일 보안 검증 | 🔴 High | 2-3시간 |
| 빌드 & 테스트 | 🔴 High | 1시간 |
| Rate Limiting | 🟡 Medium | 2-3시간 |
| HTTPS 설정 | 🟡 Medium | 2-3시간 |
| **Total (High)** | - | **4-6시간** |
| **Total (All)** | - | **8-12시간** |

---

## ✅ 성공 기준

### Phase 4 완료 조건
1. ✅ File Upload API에 JWT 인증 추가됨
2. ✅ 사용자는 본인 파일만 조회/삭제 가능
3. ✅ 악성 파일 업로드 차단됨 (.exe, zip bomb 등)
4. ✅ 기존 시스템은 영향 없음 (롤백 가능)
5. ✅ 문서화 완료

### 테스트 체크리스트
- [ ] JWT 없이 API 호출 → 401 Unauthorized
- [ ] 만료된 JWT → 401 Unauthorized
- [ ] 타 사용자 파일 접근 → 403 Forbidden
- [ ] 관리자는 모든 파일 접근 가능
- [ ] .exe 파일 업로드 차단
- [ ] 정상 파일은 업로드 성공
- [ ] 기존 Job Submit 정상 작동
- [ ] Template 선택 정상 작동

---

## 🔄 롤백 계획

### 롤백 시나리오
1. JWT 인증 추가 후 문제 발생
2. File Upload API 작동 불가

### 롤백 방법
```bash
# 1. Git으로 이전 버전 복구
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010
git checkout HEAD~1 file_upload_api.py

# 2. Backend 재시작
sudo systemctl restart dashboard_backend

# 3. 검증
curl http://localhost:5010/api/v2/files/health
```

### 롤백 후 복구
- 데이터 손실 없음 (DB 스키마 변경 없음)
- 업로드된 파일은 그대로 유지
- Frontend 변경 없음 (JWT는 이미 전송 중)

---

## 📝 다음 Phase 미리보기

### Phase 5: Performance Optimization
- Frontend 코드 스플리팅 (1.48MB bundle 개선)
- DB 인덱싱
- 캐싱 전략
- WebSocket 최적화

### Phase 6: Testing & Documentation
- Unit tests
- Integration tests
- E2E tests
- API 문서화 (Swagger)

---

**End of Phase 4 Plan v4.4.0**
