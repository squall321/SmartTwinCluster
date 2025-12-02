# Phase 2: JWT Integration into Existing Services

JWT 인증을 기존 Dashboard Backend (backend_5010)에 통합

---

## 📋 Phase 2 개요

Phase 1에서 구축한 Auth Portal의 JWT 토큰을 기존 HPC Dashboard 서비스에 통합하여 인증된 사용자만 API를 사용할 수 있도록 합니다.

**목표:**
- ✅ JWT 미들웨어 구현
- ✅ 기존 backend_5010 API에 JWT 인증 적용
- 🔄 frontend_3010에서 JWT 토큰 사용 (진행 예정)
- 🔄 토큰 만료 시 Auth Portal로 리다이렉트 (진행 예정)

---

## 🔧 Phase 2 Backend 완료 사항

### 1. JWT 미들웨어 생성

**파일:** [backend_5010/middleware/jwt_middleware.py](backend_5010/middleware/jwt_middleware.py)

4가지 데코레이터 제공:

```python
from middleware.jwt_middleware import jwt_required, permission_required, group_required, optional_jwt

# 1. JWT 필수 인증
@jwt_required
def protected_endpoint():
    user = g.user  # {'username', 'email', 'groups', 'permissions'}

# 2. 특정 권한 필요
@permission_required('dashboard', 'admin')
def admin_only_endpoint():
    pass

# 3. 특정 그룹 필요
@group_required('HPC-Admins')
def admins_only_endpoint():
    pass

# 4. JWT 선택적 (있으면 검증, 없어도 OK)
@optional_jwt
def public_endpoint():
    user = g.get('user')  # JWT 있으면 user 정보, 없으면 None
```

### 2. Backend JWT 적용 완료

**적용된 엔드포인트:**

| 엔드포인트 | 메소드 | JWT | 권한 요구사항 | 설명 |
|----------|--------|-----|---------------|------|
| `/api/slurm/jobs/submit` | POST | ✅ 필수 | `dashboard` | 작업 제출 |
| `/api/slurm/jobs/<id>/cancel` | POST | ✅ 필수 | `dashboard` | 작업 취소 |
| `/api/slurm/jobs/<id>/hold` | POST | ✅ 필수 | `dashboard` | 작업 홀드 |
| `/api/slurm/jobs/<id>/release` | POST | ✅ 필수 | `dashboard` | 작업 릴리즈 |
| `/api/slurm/apply-config` | POST | ✅ 필수 | `dashboard` + `admin` | 클러스터 설정 변경 |
| `/api/slurm/status` | GET | 🔓 선택적 | - | Slurm 상태 조회 |
| `/api/health` | GET | 🔓 공개 | - | 헬스 체크 |
| `/api/metrics` | GET | 🔓 공개 | - | Prometheus 메트릭 |

**적용 패턴:**
```python
# 예시 1: 작업 제출 (dashboard 권한 필요)
@app.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required
@permission_required('dashboard')
def submit_job():
    """작업 제출 - JWT 인증 필요"""
    user = g.user
    # user['username'], user['permissions'], user['groups'] 사용 가능
    ...

# 예시 2: 설정 변경 (admin 권한 필요)
@app.route('/api/slurm/apply-config', methods=['POST'])
@jwt_required
@permission_required('dashboard', 'admin')
def apply_slurm_config():
    """설정 적용 - JWT 인증 및 admin 권한 필요"""
    ...
```

### 3. 환경 변수 설정

**파일:** [backend_5010/.env](backend_5010/.env)

```env
# Backend 모드
MOCK_MODE=true

# JWT 설정 (Auth Portal과 동일해야 함!)
JWT_SECRET_KEY=your-jwt-secret-key-change-this-in-production
JWT_ALGORITHM=HS256

# Auth Portal URL
AUTH_PORTAL_URL=http://localhost:4430
```

⚠️ **중요:** `JWT_SECRET_KEY`는 Auth Portal([auth_portal_4430/.env](auth_portal_4430/.env))과 **반드시 동일**해야 합니다!

### 4. 의존성 추가

**파일:** [backend_5010/requirements.txt](backend_5010/requirements.txt)

추가된 패키지:
```
PyJWT==2.8.0
python-dotenv==1.0.0
```

설치:
```bash
cd backend_5010
source venv/bin/activate
pip install -r requirements.txt
```

---

## 🔄 Phase 2 Frontend 작업 (진행 예정)

### 1. JWT 토큰 수신 및 저장

**파일:** `frontend_3010/src/App.tsx` (수정 필요)

```typescript
// URL에서 토큰 추출 (ServiceMenu에서 전달됨)
const urlParams = new URLSearchParams(window.location.search);
const token = urlParams.get('token');

if (token) {
  // localStorage에 저장
  localStorage.setItem('jwt_token', token);

  // URL에서 토큰 제거 (보안)
  window.history.replaceState({}, document.title, window.location.pathname);
}
```

### 2. Axios Interceptor 설정

**파일:** `frontend_3010/src/api/axiosConfig.ts` (생성 필요)

```typescript
import axios from 'axios';

const api = axios.create({
  baseURL: 'http://localhost:5010/api',
  timeout: 10000,
});

// 요청 인터셉터: 모든 요청에 JWT 토큰 추가
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('jwt_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// 응답 인터셉터: 401 에러 시 Auth Portal로 리다이렉트
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // 토큰 만료 또는 유효하지 않음
      localStorage.removeItem('jwt_token');
      window.location.href = 'http://localhost:4431'; // Auth Portal Frontend
    }
    return Promise.reject(error);
  }
);

export default api;
```

### 3. 기존 API 호출 수정

기존 `fetch()` 또는 `axios()` 호출을 위에서 만든 `api` 인스턴스로 교체:

```typescript
// Before
const response = await fetch('/api/slurm/jobs');

// After
import api from './api/axiosConfig';
const response = await api.get('/slurm/jobs');
```

---

## 🧪 테스트

### 1. JWT 없이 API 호출 (401 에러 예상)

```bash
# 작업 제출 시도 (JWT 없음)
curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -d '{
    "jobName": "test_job",
    "partition": "group1",
    "nodes": 1,
    "script": "echo Hello"
  }'

# 예상 응답: {"error": "No authorization header"}, 401
```

### 2. 테스트 토큰 발급

```bash
# Auth Portal에서 테스트 토큰 발급
TOKEN=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "email": "admin@hpc.local",
    "groups": ["HPC-Admins"]
  }' | jq -r '.token')

echo "Token: $TOKEN"
```

### 3. JWT와 함께 API 호출 (성공 예상)

```bash
# 작업 제출 시도 (JWT 포함)
curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jobName": "test_job",
    "partition": "group1",
    "nodes": 1,
    "cpus": 128,
    "memory": "16GB",
    "time": "01:00:00",
    "script": "echo Hello World"
  }'

# 예상 응답: {"success": true, "jobId": "10001", ...}
```

### 4. 권한 없는 사용자 테스트

```bash
# GPU-Users 그룹 사용자 (dashboard 권한 없음)
TOKEN_GPU=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "gpu_user",
    "email": "gpu_user@hpc.local",
    "groups": ["GPU-Users"]
  }' | jq -r '.token')

# 작업 제출 시도
curl -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN_GPU" \
  -d '{
    "jobName": "test_job",
    "partition": "group1",
    "nodes": 1,
    "script": "echo Hello"
  }'

# 예상 응답: {"error": "Forbidden"}, 403
```

### 5. Admin 전용 엔드포인트 테스트

```bash
# Admin 권한 필요한 설정 변경
curl -X POST http://localhost:5010/api/slurm/apply-config \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "groups": [...],
    "dryRun": true
  }'

# Admin 권한이 있는 토큰($TOKEN)은 성공
# HPC-Users 그룹은 dashboard 권한만 있어서 403 에러
```

---

## 📝 그룹별 권한 매핑

| 그룹 | 권한 | Dashboard 접근 | 작업 제출 | 설정 변경 |
|------|------|---------------|----------|----------|
| **HPC-Admins** | `dashboard`, `cae`, `vnc`, `admin` | ✅ | ✅ | ✅ |
| **HPC-Users** | `dashboard`, `vnc` | ✅ | ✅ | ❌ |
| **GPU-Users** | `vnc` | ❌ | ❌ | ❌ |
| **Automation-Users** | `cae` | ❌ | ❌ | ❌ |

---

## 🔍 JWT Payload 구조

Auth Portal에서 발급하는 JWT 토큰의 payload:

```json
{
  "sub": "admin",                    // username
  "email": "admin@hpc.local",
  "groups": ["HPC-Admins"],
  "permissions": ["dashboard", "cae", "vnc", "admin"],
  "iat": 1697654321,                 // issued at
  "exp": 1697682321,                 // expires (8시간 후)
  "iss": "auth-portal"               // issuer
}
```

Backend에서 `g.user`로 접근 가능:
```python
user = g.user
print(user['username'])      # "admin"
print(user['email'])         # "admin@hpc.local"
print(user['groups'])        # ["HPC-Admins"]
print(user['permissions'])   # ["dashboard", "cae", "vnc", "admin"]
```

---

## 🚀 다음 단계

### Phase 2 완료 체크리스트

Backend:
- [x] JWT 미들웨어 생성
- [x] 작업 관리 엔드포인트에 JWT 적용
- [x] 설정 변경 엔드포인트에 admin 권한 적용
- [x] .env 파일 설정
- [x] 의존성 설치

Frontend (진행 예정):
- [ ] URL에서 JWT 토큰 추출 및 저장
- [ ] Axios interceptor 설정
- [ ] 기존 API 호출에 JWT 헤더 추가
- [ ] 401 에러 시 Auth Portal로 리다이렉트
- [ ] 토큰 만료 시 재로그인 프롬프트

테스트:
- [ ] JWT 없이 호출 → 401 확인
- [ ] JWT와 함께 호출 → 성공 확인
- [ ] 권한 없는 사용자 → 403 확인
- [ ] Admin 전용 엔드포인트 → 권한 체크 확인

---

## 📚 참고 문서

- [Phase 1: Auth Portal](PHASE1_README.md)
- [JWT 미들웨어 소스](backend_5010/middleware/jwt_middleware.py)
- [Backend .env 설정](backend_5010/.env)
- [Auth Portal 설정](auth_portal_4430/.env)

---

**작성일**: 2025-10-16
**버전**: Phase 2.0 (Backend 완료)
