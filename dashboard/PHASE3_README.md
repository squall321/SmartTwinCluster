# Phase 3: Dashboard Frontend JWT Integration

Dashboard Frontend에 JWT 인증 통합 완료

---

## 📋 Phase 3 개요

Phase 2에서 Backend에 JWT 미들웨어를 적용한 것에 이어, Phase 3에서는 Dashboard Frontend(포트 3010)가 Auth Portal에서 발급받은 JWT 토큰을 사용하여 Backend API를 호출하도록 통합합니다.

**목표:**
- ✅ JWT 토큰을 URL에서 추출하여 localStorage에 저장
- ✅ 모든 API 요청에 JWT 토큰 자동 포함
- ✅ 401 에러 발생 시 Auth Portal로 자동 리다이렉트
- ✅ 인증 흐름 end-to-end 테스트 완료

---

## 🔧 Phase 3 완료 사항

### 1. JWT Token Management (utils/api.ts)

**파일:** [frontend_3010/src/utils/api.ts](frontend_3010/src/utils/api.ts)

JWT 토큰 관리 함수 추가:

```typescript
// JWT Token Management Functions
function getJwtToken(): string | null {
  return localStorage.getItem('jwt_token');
}

export function setJwtToken(token: string): void {
  localStorage.setItem('jwt_token', token);
  console.log('[Auth] JWT token saved to localStorage');
}

export function clearJwtToken(): void {
  localStorage.removeItem('jwt_token');
  console.log('[Auth] JWT token cleared from localStorage');
}

export function isAuthenticated(): boolean {
  return getJwtToken() !== null;
}

function redirectToAuthPortal(): void {
  console.log('[Auth] Redirecting to Auth Portal due to authentication failure');
  clearJwtToken();
  window.location.href = AUTH_PORTAL_URL;
}
```

### 2. Automatic JWT Header Injection

**위치:** [frontend_3010/src/utils/api.ts:206-217](frontend_3010/src/utils/api.ts#L206-L217)

모든 API 요청에 JWT 토큰을 자동으로 추가:

```typescript
export async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {},
  skipRetry: boolean = false
): Promise<T> {
  const url = `${API_BASE_URL}${endpoint}`;

  // Add JWT token to headers if available
  const token = getJwtToken();
  const authHeaders = token ? { 'Authorization': `Bearer ${token}` } : {};

  const defaultOptions: RequestInit = {
    headers: {
      'Content-Type': 'application/json',
      ...authHeaders,
      ...options.headers,
    },
    ...options,
  };
  // ... rest of the function
}
```

### 3. 401 Error Interceptor

**위치:** [frontend_3010/src/utils/api.ts:243-249](frontend_3010/src/utils/api.ts#L243-L249)

API 응답에서 401 Unauthorized 에러를 감지하고 Auth Portal로 리다이렉트:

```typescript
if (!response.ok) {
  // Handle 401 Unauthorized - token expired or invalid
  if (response.status === 401) {
    console.warn('[Auth] 401 Unauthorized - redirecting to Auth Portal');
    redirectToAuthPortal();
    throw new ApiError('Authentication required', 401, endpoint);
  }
  // ... handle other errors
}
```

### 4. JWT Token Extraction (App.tsx)

**파일:** [frontend_3010/src/App.tsx](frontend_3010/src/App.tsx)

URL 쿼리 파라미터에서 JWT 토큰을 추출하고 localStorage에 저장:

```typescript
import React, { useEffect } from 'react';
import { setJwtToken } from './utils/api';

function App() {
  useEffect(() => {
    // Extract JWT token from URL query parameters (from Auth Portal)
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');

    if (token) {
      console.log('[Auth] JWT token received from URL, storing in localStorage');
      setJwtToken(token);

      // Remove token from URL for security (prevent token exposure in browser history)
      window.history.replaceState({}, document.title, window.location.pathname);
    }
  }, []);

  return (
    <ThemeProvider>
      <Dashboard />
    </ThemeProvider>
  );
}
```

---

## 🔄 인증 플로우

### End-to-End 인증 과정

```
[1] User → Auth Portal Frontend (http://localhost:4431)
     │
     └─ Test Login 클릭 (또는 SSO)
     │
[2] Auth Portal Backend → JWT 토큰 발급
     │
     └─ localStorage에 'jwt_token' 저장
     │
[3] User → Service Menu에서 "HPC Dashboard" 선택
     │
     └─ ServiceMenuPage.tsx (Line 82):
         window.location.href = `${service.url}?token=${token}`
     │
[4] Dashboard Frontend → App.tsx (useEffect)
     │
     └─ URL 파라미터에서 token 추출
     └─ setJwtToken(token) → localStorage 저장
     └─ URL에서 token 제거 (보안)
     │
[5] Dashboard → API 요청 시
     │
     └─ apiRequest() 함수가 자동으로 헤더 추가:
         Authorization: Bearer <token>
     │
[6] Backend → JWT 미들웨어가 토큰 검증
     │
     ├─ 유효 → API 처리 후 응답
     └─ 무효/만료 → 401 에러
                    │
                    └─ Frontend가 401 감지
                        → Auth Portal로 리다이렉트
```

---

## 🧪 테스트

### 자동 테스트 스크립트

**파일:** [/tmp/test_jwt_api.sh](/tmp/test_jwt_api.sh)

```bash
#!/bin/bash

# Get JWT token
TOKEN=$(curl -s -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","email":"admin@hpc.local","groups":["HPC-Admins"]}' | jq -r '.token')

# Test 1: Without JWT (should fail)
curl -s -X POST http://localhost:5010/api/slurm/jobs/submit \
  -H "Content-Type: application/json" \
  -d '{"jobName":"test","partition":"group1","nodes":1}' | jq

# Test 2: With JWT (should succeed)
curl -s -X POST http://localhost:5010/api/slurm/jobs/submit \
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
  }' | jq
```

**실행:**
```bash
chmod +x /tmp/test_jwt_api.sh
/tmp/test_jwt_api.sh
```

**예상 결과:**

Test 1 (JWT 없음):
```json
{
  "error": "No authorization header",
  "message": "Authorization header is required"
}
```

Test 2 (JWT 포함):
```json
{
  "jobId": "10002",
  "message": "Job 10002 submitted successfully (Mock)",
  "mode": "mock",
  "success": true
}
```

### 수동 브라우저 테스트

1. **Auth Portal 접속**
   ```
   http://localhost:4431
   ```

2. **Test Login 사용**
   - "Developer Test Login" 섹션 확장
   - Username: `admin`
   - Group: `HPC-Admins`
   - "Test Login" 버튼 클릭

3. **Service Menu 확인**
   - 로그인 성공 후 서비스 목록 표시
   - "HPC Dashboard" 카드 클릭

4. **Dashboard 접속**
   - URL이 `http://localhost:3010?token=...`로 변경됨
   - 자동으로 `http://localhost:3010`으로 정리됨 (보안)
   - 브라우저 개발자 도구 → Application → Local Storage 확인
     - `jwt_token` 키 존재 확인

5. **API 호출 테스트**
   - Dashboard에서 작업 제출 시도
   - 브라우저 개발자 도구 → Network 탭
   - 요청 헤더에 `Authorization: Bearer <token>` 포함 확인

6. **401 에러 테스트**
   - localStorage에서 jwt_token 삭제:
     ```javascript
     localStorage.removeItem('jwt_token')
     ```
   - 페이지 새로고침 후 API 호출 시도
   - Auth Portal로 자동 리다이렉트 확인

---

## 📊 수정된 파일 요약

| 파일 | 변경 내용 | 라인 |
|------|----------|------|
| [frontend_3010/src/utils/api.ts](frontend_3010/src/utils/api.ts) | JWT 토큰 관리 함수 추가 | 20-60 |
| [frontend_3010/src/utils/api.ts](frontend_3010/src/utils/api.ts) | 자동 JWT 헤더 추가 | 206-217 |
| [frontend_3010/src/utils/api.ts](frontend_3010/src/utils/api.ts) | 401 에러 인터셉터 | 243-249 |
| [frontend_3010/src/App.tsx](frontend_3010/src/App.tsx) | URL 토큰 추출 및 저장 | 8-20 |

---

## 🔐 보안 고려사항

### 1. Token Storage
- ✅ JWT 토큰을 localStorage에 저장
- ⚠️ XSS 공격에 취약할 수 있음
- 💡 Production 환경에서는 HttpOnly Cookie 사용 고려

### 2. Token in URL
- ✅ URL에서 토큰을 즉시 제거 (`window.history.replaceState`)
- ✅ 브라우저 히스토리에 토큰이 남지 않음
- ⚠️ URL이 서버 로그에 기록될 수 있음
- 💡 Alternative: POST 방식으로 토큰 전달

### 3. Token Expiration
- ✅ 8시간 유효 (Auth Portal 설정)
- ✅ 만료 시 401 에러 → 자동 리다이렉트
- ✅ 사용자가 재로그인하여 새 토큰 발급

### 4. HTTPS
- ⚠️ 현재 HTTP 사용 (개발 환경)
- 🚨 **Production에서는 반드시 HTTPS 사용**
- 💡 Nginx에서 SSL/TLS 설정 필요

---

## 🚀 다음 단계

### Phase 3 완료 체크리스트

- [x] JWT 토큰 관리 함수 구현
- [x] 자동 JWT 헤더 추가
- [x] 401 에러 인터셉터 구현
- [x] App.tsx에서 URL 토큰 추출
- [x] End-to-end 테스트 완료

### Phase 4: Production Mode (예정)

Phase 3까지는 **Mock Mode**로 작동합니다. Phase 4에서는:

1. **실제 Slurm 클러스터 연결**
   - Mock 데이터 → Slurm 명령어 (sinfo, squeue, sbatch)
   - [backend_5010/services/slurm_service.py](backend_5010/services/slurm_service.py) 수정

2. **환경 변수 설정**
   ```bash
   # backend_5010/.env
   MOCK_MODE=false  # Production mode로 전환
   ```

3. **Slurm 권한 설정**
   - Backend 실행 계정이 Slurm 명령어 사용 가능해야 함
   - `/etc/sudoers` 설정 또는 setuid 권한 필요

4. **실제 작업 제출 테스트**
   ```bash
   # 실제 노드에서 작업 실행 확인
   squeue -u <username>
   ```

---

## 📚 참고 문서

- [Phase 0: Infrastructure Setup](setup_phase0_all.sh)
- [Phase 1: Auth Portal](PHASE1_README.md)
- [Phase 2: Backend JWT Integration](PHASE2_README.md)
- [User Guide](USER_GUIDE.md)
- [Quick Reference](QUICK_REFERENCE.md)

---

## 🎉 Phase 3 완료!

이제 HPC Dashboard는 완전한 SSO 인증 기반으로 작동합니다:

```
✅ Auth Portal (4431) - Test Login 지원
✅ Auth Backend (4430) - JWT 발급/검증
✅ Dashboard Backend (5010) - JWT 미들웨어
✅ Dashboard Frontend (3010) - JWT 자동 전송 및 401 처리
✅ Redis (6379) - 세션 관리
```

**전체 인증 플로우가 작동합니다!** 🎊

---

**작성일**: 2025-10-16
**버전**: Phase 3.0 (Frontend JWT Integration 완료)
