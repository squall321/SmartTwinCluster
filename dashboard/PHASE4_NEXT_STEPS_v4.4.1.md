# Phase 4: 다음 단계 (v4.4.1+)

**현재 완료**: Phase 4.4.0 - JWT 인증 & 파일 보안 검증 (High Priority 완료)
**날짜**: 2025-11-05
**상태**: ✅ High Priority 완료, Medium/Low Priority 남음

---

## 📊 Phase 4 완료 상태

### ✅ 완료된 항목 (High Priority)

#### 1. File Upload API JWT 인증 ✅
- **상태**: 100% 완료
- **구현 내용**:
  - 모든 엔드포인트에 `@jwt_required` 데코레이터 추가
  - `@permission_required('dashboard')` 권한 검증
  - user_id를 JWT 토큰에서 추출 (보안 강화)
  - 권한 기반 접근 제어 (사용자 격리)
  - 프론트엔드 ChunkUploader JWT 토큰 통합
- **파일**:
  - `backend_5010/file_upload_api.py`
  - `frontend_3010/src/utils/ChunkUploader.ts`
- **문서**: `PHASE4_SECURITY_v4.4.0.md`

#### 2. 파일 보안 검증 ✅
- **상태**: 100% 완료
- **구현 내용**:
  - `validate_file_security()` 메서드 추가
  - 위험한 실행 파일 차단 (.exe, .dll, .so)
  - 의심스러운 스크립트 차단 (.bat, .cmd, .vbs, .ps1)
  - 파일명 패턴 검증 (virus, malware, trojan 등)
  - 파일 크기 검증 (0 bytes, 50GB 초과)
  - HPC 스크립트 허용 (.sh, .py, .sbatch, .f90, .c, .cpp)
  - 압축 파일 경고 (.zip, .tar.gz)
- **파일**:
  - `backend_5010/file_classifier.py`
  - `backend_5010/file_upload_api.py` (통합)
- **문서**: `PHASE4_SECURITY_v4.4.0.md`

#### 3. 프로덕션 배포 준비 ✅
- **상태**: 100% 완료
- **검증 내용**:
  - 백엔드 서비스 정상 실행
  - JWT 인증 정상 작동
  - 경로 및 디렉토리 검증
  - VNC/CAE 서비스 통합 확인
  - WebSocket 연동 확인
  - 프론트엔드 빌드 완료
- **문서**: `PHASE4_PRODUCTION_READINESS_v4.4.0.md`

---

## 🎯 다음 할 일 (Phase 4 나머지)

### 🟡 Medium Priority (권장 - 프로덕션 전 완료)

#### 1. WebSocket JWT 인증 추가 (Phase 4.4)
**우선순위**: Medium
**예상 시간**: 2-3시간
**중요도**: 보안 강화 (현재도 안전하지만 개선 가능)

**현재 상태**:
- WebSocket 연결 시 JWT 검증 없음
- 누구나 WebSocket에 연결 가능 (읽기만 가능)
- 민감한 정보는 없지만, 사용자별 업로드 진행률 노출 가능

**구현 계획**:
```python
# websocket_server.py 수정 (최소한의 변경)

async def websocket_handler(request):
    """WebSocket 연결 핸들러 (JWT 검증 추가)"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    # JWT 토큰 검증 (WebSocket 연결 시)
    token = request.query.get('token') or request.headers.get('Authorization', '').replace('Bearer ', '')

    if not token:
        await ws.send_json({
            'type': 'error',
            'message': 'Authentication required'
        })
        await ws.close()
        return ws

    try:
        # JWT 검증
        from middleware.jwt_middleware import verify_jwt_token  # 새 함수 추가 필요
        user_info = verify_jwt_token(token)

        # 연결 추가 (사용자 정보 포함)
        connected_clients[ws] = user_info

        # 초기 데이터 전송 (사용자 필터링)
        initial_data = await get_initial_storage_data(user_info)
        await ws.send_json({
            'type': 'initial_data',
            'data': initial_data
        })

    except Exception as e:
        await ws.send_json({
            'type': 'error',
            'message': 'Invalid token'
        })
        await ws.close()
        return ws
```

**프론트엔드 수정**:
```typescript
// useWebSocket.ts 수정
const token = localStorage.getItem('jwt_token');
const ws = new WebSocket(`ws://localhost:5011/ws?token=${token}`);
```

**롤백 계획**:
- WebSocket 서버만 재시작하면 복구 가능
- 기존 코드 주석 처리하고 새 코드 추가
- 문제 발생 시 주석 해제 후 재시작

**파일 수정**:
1. `backend_5010/websocket_server.py` (WebSocket 핸들러)
2. `backend_5010/middleware/jwt_middleware.py` (verify_jwt_token 함수 추가)
3. `frontend_3010/src/hooks/useWebSocket.ts` (토큰 전송)

**테스트 계획**:
1. JWT 없이 연결 시도 → 401 에러 확인
2. 유효한 JWT로 연결 → 정상 연결 확인
3. 만료된 JWT로 연결 → 401 에러 확인
4. 사용자별 데이터 필터링 확인

---

#### 2. Rate Limiting 추가 (Phase 4.6)
**우선순위**: Medium
**예상 시간**: 2-3시간
**중요도**: API 남용 방지

**현재 상태**:
- Rate limiting 없음
- 사용자가 무제한으로 API 호출 가능
- 파일 업로드 API에 특히 취약

**구현 계획**:
```python
# backend_5010/middleware/rate_limiter.py (새 파일)

from functools import wraps
from flask import request, jsonify, g
from datetime import datetime, timedelta
from collections import defaultdict
import threading

# 메모리 기반 Rate Limiter
class RateLimiter:
    def __init__(self):
        self.requests = defaultdict(list)  # {user_id: [timestamps]}
        self.lock = threading.Lock()

    def is_allowed(self, user_id: str, max_requests: int, window_seconds: int) -> bool:
        """Rate limit 체크"""
        with self.lock:
            now = datetime.now()
            cutoff = now - timedelta(seconds=window_seconds)

            # 오래된 요청 제거
            self.requests[user_id] = [
                ts for ts in self.requests[user_id]
                if ts > cutoff
            ]

            # 요청 수 확인
            if len(self.requests[user_id]) >= max_requests:
                return False

            # 새 요청 추가
            self.requests[user_id].append(now)
            return True

rate_limiter = RateLimiter()

def rate_limit(max_requests: int = 100, window_seconds: int = 60):
    """
    Rate limiting 데코레이터

    Usage:
        @jwt_required
        @rate_limit(max_requests=10, window_seconds=60)
        def upload_file():
            ...
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = g.get('user')
            if not user:
                return jsonify({'error': 'Unauthorized'}), 401

            user_id = user['username']

            if not rate_limiter.is_allowed(user_id, max_requests, window_seconds):
                return jsonify({
                    'error': 'Rate limit exceeded',
                    'message': f'Maximum {max_requests} requests per {window_seconds} seconds',
                    'retry_after': window_seconds
                }), 429

            return f(*args, **kwargs)

        return decorated_function
    return decorator
```

**적용 예시**:
```python
# file_upload_api.py
from middleware.rate_limiter import rate_limit

@file_upload_bp.route('/api/v2/files/upload/init', methods=['POST'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=10, window_seconds=60)  # 분당 10회 제한
def init_upload():
    ...

@file_upload_bp.route('/api/v2/files/upload/chunk', methods=['POST'])
@jwt_required
@permission_required('dashboard')
@rate_limit(max_requests=1000, window_seconds=60)  # 분당 1000 청크 (대용량 파일)
def upload_chunk():
    ...
```

**파일 수정**:
1. `backend_5010/middleware/rate_limiter.py` (새 파일)
2. `backend_5010/file_upload_api.py` (데코레이터 추가)
3. `backend_5010/app.py` (Job Submit API에도 추가)

**테스트 계획**:
1. 제한 횟수 초과 시 429 에러 확인
2. 시간 경과 후 다시 가능한지 확인
3. 여러 사용자 동시 접속 시 격리 확인

---

#### 3. HTTPS 설정 (Phase 4.5)
**우선순위**: Medium (프로덕션 필수)
**예상 시간**: 3-4시간
**중요도**: 보안 필수 (JWT 토큰 보호)

**현재 상태**:
- HTTP만 사용 (포트 3010, 5010)
- JWT 토큰이 평문으로 전송됨
- 중간자 공격 가능

**구현 계획**:
```nginx
# /etc/nginx/sites-available/dashboard

# Frontend (Port 3010 → HTTPS 443)
server {
    listen 443 ssl http2;
    server_name dashboard.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/dashboard.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dashboard.yourdomain.com/privkey.pem;

    # SSL 설정
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Frontend static files
    location / {
        root /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010/dist;
        try_files $uri $uri/ /index.html;
    }

    # API Proxy (Backend 5010)
    location /api/ {
        proxy_pass http://localhost:5010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket Proxy (5011)
    location /ws {
        proxy_pass http://localhost:5011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}

# HTTP → HTTPS 리다이렉트
server {
    listen 80;
    server_name dashboard.yourdomain.com;
    return 301 https://$server_name$request_uri;
}
```

**Let's Encrypt 인증서 발급**:
```bash
# Certbot 설치
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# 인증서 발급
sudo certbot --nginx -d dashboard.yourdomain.com

# 자동 갱신 설정
sudo certbot renew --dry-run
```

**프론트엔드 설정**:
```typescript
// src/config/api.config.ts
export const API_CONFIG = {
  BASE_URL: import.meta.env.PROD
    ? 'https://dashboard.yourdomain.com'
    : 'http://localhost:5010',
  WEBSOCKET_URL: import.meta.env.PROD
    ? 'wss://dashboard.yourdomain.com/ws'
    : 'ws://localhost:5011/ws',
};
```

**파일 수정**:
1. `/etc/nginx/sites-available/dashboard` (새 파일)
2. `frontend_3010/src/config/api.config.ts`
3. `frontend_3010/.env.production` (환경 변수)

**테스트 계획**:
1. HTTPS 접속 확인
2. HTTP → HTTPS 리다이렉트 확인
3. WebSocket wss:// 연결 확인
4. JWT 토큰 암호화 전송 확인

---

### 🟢 Low Priority (선택적 - Phase 5로 연기 가능)

#### 4. Audit Logging (Phase 4.7)
**우선순위**: Low
**예상 시간**: 3-4시간
**중요도**: 규정 준수, 보안 감사

**구현 계획**:
- 모든 파일 업로드/다운로드 기록
- 사용자 인증 이벤트 로깅
- 권한 변경 이벤트 로깅
- SQLite 또는 별도 로그 파일

**파일 수정**:
1. `backend_5010/middleware/audit_logger.py` (새 파일)
2. `backend_5010/file_upload_api.py` (로깅 추가)

---

#### 5. 파일 암호화 (Phase 4.8)
**우선순위**: Low
**예상 시간**: 4-5시간
**중요도**: 데이터 보호 (저장소 침해 대비)

**구현 계획**:
- 업로드된 파일 자동 암호화 (AES-256)
- 다운로드 시 자동 복호화
- 키 관리 시스템 필요

**파일 수정**:
1. `backend_5010/file_encryption.py` (새 파일)
2. `backend_5010/file_upload_api.py` (암호화 통합)

---

#### 6. 바이러스 스캔 (ClamAV 통합) (Phase 4.9)
**우선순위**: Low
**예상 시간**: 3-4시간
**중요도**: 악성 파일 차단 (현재는 확장자만 검사)

**구현 계획**:
- ClamAV 설치 및 연동
- 업로드 완료 후 자동 스캔
- 악성 파일 발견 시 자동 삭제

**파일 수정**:
1. `backend_5010/virus_scanner.py` (새 파일)
2. `backend_5010/file_upload_api.py` (스캔 통합)

---

## 📋 권장 구현 순서

### 즉시 구현 (프로덕션 전 필수)
1. ✅ **File Upload API JWT 인증** - 완료
2. ✅ **파일 보안 검증** - 완료
3. 🟡 **HTTPS 설정** - 프로덕션 배포 전 필수!

### 프로덕션 초기 (1-2주 내)
4. 🟡 **Rate Limiting** - API 남용 방지
5. 🟡 **WebSocket JWT 인증** - 보안 강화

### 장기 계획 (Phase 5로 연기 가능)
6. 🟢 **Audit Logging** - 규정 준수
7. 🟢 **파일 암호화** - 데이터 보호
8. 🟢 **바이러스 스캔** - 악성 파일 차단

---

## 🎯 Phase 4.4.1 추천 작업

**다음으로 추천하는 작업**:

### 옵션 1: HTTPS 설정 (가장 중요!)
- **이유**: JWT 토큰 보호 필수
- **영향**: 보안 크게 향상
- **시간**: 3-4시간
- **프로덕션**: 필수

### 옵션 2: Rate Limiting
- **이유**: API 남용 방지
- **영향**: 서버 안정성 향상
- **시간**: 2-3시간
- **프로덕션**: 권장

### 옵션 3: WebSocket JWT 인증
- **이유**: 완전한 보안 체계
- **영향**: 보안 향상
- **시간**: 2-3시간
- **프로덕션**: 선택적

---

## 📊 Phase 4 전체 진행률

```
Phase 4.0: 기획 및 분석          ✅ 100%
Phase 4.1: JWT 인증 추가         ✅ 100%
Phase 4.2: 파일 보안 검증        ✅ 100%
Phase 4.3: 프로덕션 배포 준비    ✅ 100%
─────────────────────────────────────────
High Priority                    ✅ 100% (완료)

Phase 4.4: WebSocket JWT         ⏳ 0%
Phase 4.5: HTTPS 설정           ⏳ 0%
Phase 4.6: Rate Limiting        ⏳ 0%
─────────────────────────────────────────
Medium Priority                  ⏳ 0% (3개 남음)

Phase 4.7: Audit Logging        ⏳ 0%
Phase 4.8: 파일 암호화           ⏳ 0%
Phase 4.9: 바이러스 스캔         ⏳ 0%
─────────────────────────────────────────
Low Priority                     ⏳ 0% (3개 남음)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
전체 진행률: 33% (3/9 완료)
```

---

## ✅ 다음 세션 시작 방법

### 1. HTTPS 설정을 하려면:
```
"HTTPS 설정을 시작하자. Nginx 설정과 Let's Encrypt 인증서 발급부터 해줘."
```

### 2. Rate Limiting을 하려면:
```
"Rate Limiting 미들웨어를 만들자. 파일 업로드 API에 적용해줘."
```

### 3. WebSocket JWT 인증을 하려면:
```
"WebSocket 서버에 JWT 인증을 추가하자. 기존 코드는 건드리지 말고."
```

### 4. 다른 Phase로 넘어가려면:
```
"Phase 4는 High Priority만 완료했으니, Phase 5로 넘어가자."
```

---

## 📞 문의 사항

Phase 4 나머지 작업에 대한 질문이나, 다른 Phase로 넘어가고 싶으면 말씀해주세요!

**현재 상태**: Phase 4 High Priority 완료, 프로덕션 배포 가능
**추천**: HTTPS 설정 (프로덕션 필수) 또는 Phase 5로 진행
