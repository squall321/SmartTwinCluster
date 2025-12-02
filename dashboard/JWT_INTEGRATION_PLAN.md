# JWT 인증 통합 계획

> **작성일**: 2025-11-06
> **목적**: Job Submit 플로우에 JWT 인증을 일관되게 적용
> **상태**: 🔍 분석 완료 → 📋 계획 수립

---

## 📊 현재 상황 분석

### ✅ JWT 인증이 이미 적용된 부분

#### 1. **전역 인증 시스템**
- **AuthContext** ([AuthContext.tsx:1-96](frontend_3010/src/contexts/AuthContext.tsx))
  - JWT 토큰 관리
  - 사용자 정보 파싱
  - 토큰 만료 자동 체크 (1분마다)
  - 로그아웃 처리

#### 2. **API 유틸리티**
- **api.ts** ([api.ts:1-670](frontend_3010/src/utils/api.ts))
  - `getJwtToken()`: localStorage에서 토큰 조회
  - `apiRequest()`: 모든 API 요청에 자동으로 JWT 헤더 추가
  ```typescript
  const token = getJwtToken();
  const authHeaders = token ? { 'Authorization': `Bearer ${token}` } : {};
  ```
  - `apiGet()`, `apiPost()`: JWT 자동 포함
  - 401 Unauthorized 자동 처리

#### 3. **Phase 1: Apptainer Images API**
- **useApptainerImages.ts**
  - `/api/v2/apptainer/images` - JWT 포함 ✅
  - useTemplates hook 패턴과 동일하게 구현됨

#### 4. **Phase 2: Templates API**
- **useTemplates.ts** ([useTemplates.ts:37-55](frontend_3010/src/hooks/useTemplates.ts))
  - `/api/v2/templates` - JWT 포함 ✅
  - `/api/v2/templates/{id}` - JWT 포함 ✅
  - `/api/v2/templates/scan` - JWT 포함 ✅
  ```typescript
  const getHeaders = (): HeadersInit => {
    const token = getJwtToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    return headers;
  };
  ```

#### 5. **Phase 3: File Upload API**
- **ChunkUploader.ts** ([ChunkUploader.ts:8-17](frontend_3010/src/utils/ChunkUploader.ts))
  - `/api/v2/files/upload/init` - JWT 포함 ✅
  - `/api/v2/files/upload/chunk` - JWT 포함 ✅
  - `/api/v2/files/upload/complete` - JWT 포함 ✅
  ```typescript
  function getJwtToken(): string | null {
    return localStorage.getItem('jwt_token');
  }
  function getAuthHeaders(): HeadersInit {
    const token = getJwtToken();
    return token ? { 'Authorization': `Bearer ${token}` } : {};
  }
  ```

### ❌ JWT 인증이 누락된 부분

#### **Job Submit API**
- **위치**: [JobManagement.tsx:739-743](frontend_3010/src/components/JobManagement.tsx#L739-L743)
- **문제**: `fetch()`를 직접 사용하며 JWT 헤더가 없음
  ```typescript
  const response = await fetch(`${API_CONFIG.API_BASE_URL.replace(':5010', ':5000')}/api/slurm/jobs/submit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },  // ❌ JWT 없음!
    body: JSON.stringify(submitData),
  });
  ```

---

## 🎯 문제점

### 1. **보안 취약점**
- Job Submit API가 인증 없이 호출됨
- 사용자 검증 불가
- 권한 체크 불가

### 2. **일관성 부족**
- Phase 1, 2, 3은 모두 JWT 사용
- Job Submit만 JWT 미사용
- 코드 패턴 불일치

### 3. **Backend 통합 문제**
- Backend가 JWT를 요구할 경우 401 Unauthorized 발생
- 사용자 정보를 JWT에서 추출하지 못함
- Job 소유자 추적 불가

### 4. **사용자 경험 문제**
- 토큰 만료 시 다른 API는 동작하지만 Job Submit만 실패
- 에러 메시지 불명확

---

## 📋 해결 계획

### Option 1: apiPost() 사용 (권장 ⭐)

**장점**:
- 기존 api.ts 유틸리티 활용
- JWT 자동 포함
- 에러 처리 표준화
- 자동 재시도
- 401 처리 일관성

**변경 사항**:
```typescript
// Before (현재)
const response = await fetch(`${API_CONFIG.API_BASE_URL.replace(':5010', ':5000')}/api/slurm/jobs/submit`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(submitData),
});
const data = await response.json();

// After (수정)
import { apiPost } from '../utils/api';

const data = await apiPost<{ success: boolean; jobId: string }>(
  '/api/slurm/jobs/submit',
  submitData
);
```

### Option 2: 수동으로 JWT 헤더 추가

**장점**:
- 최소한의 변경
- fetch() 그대로 사용

**단점**:
- 일관성 부족
- 에러 처리 중복
- 유지보수 어려움

**변경 사항**:
```typescript
import { getJwtToken } from '../utils/api';

const token = getJwtToken();
const headers: HeadersInit = {
  'Content-Type': 'application/json'
};
if (token) {
  headers['Authorization'] = `Bearer ${token}`;
}

const response = await fetch(`${API_CONFIG.API_BASE_URL.replace(':5010', ':5000')}/api/slurm/jobs/submit`, {
  method: 'POST',
  headers,
  body: JSON.stringify(submitData),
});
```

---

## ✅ 최종 권장 방안: Option 1

### Step 1: API 유틸리티 함수 사용

**수정할 파일**: `frontend_3010/src/components/JobManagement.tsx`

**변경 내용**:

#### 1. Import 추가
```typescript
// 기존
import { apiGet, apiPost, API_ENDPOINTS } from '../utils/api';

// 변경 없음 (이미 import되어 있음)
```

#### 2. handleSubmit 함수 수정
```typescript
const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();

  if (apiMode === 'mock') {
    toast.success('Job submitted successfully (Mock Mode)');
    onSubmit();
  } else {
    try {
      // jobId와 Apptainer 이미지를 포함하여 전송
      const submitData = {
        ...formData,
        jobId: tempJobId,
        apptainerImage: selectedApptainerImage ? {
          id: selectedApptainerImage.id,
          name: selectedApptainerImage.name,
          path: selectedApptainerImage.path,
          type: selectedApptainerImage.type,
          version: selectedApptainerImage.version
        } : undefined
      };

      // ✅ apiPost 사용 (JWT 자동 포함)
      const data = await apiPost<{ success: boolean; jobId: string; message?: string }>(
        '/api/slurm/jobs/submit',
        submitData
      );

      if (data.success) {
        toast.success(`Job ${data.jobId} submitted successfully`);
        onSubmit();
      } else {
        toast.error(data.message || 'Failed to submit job');
      }
    } catch (error) {
      // ApiError 처리
      if (error instanceof Error) {
        toast.error(`Error: ${error.message}`);
      } else {
        toast.error('An unexpected error occurred');
      }
    }
  }
};
```

### Step 2: Backend API 엔드포인트 확인

**확인 사항**:
1. Backend가 `/api/slurm/jobs/submit`에서 JWT를 검증하는가?
2. JWT에서 사용자 정보를 추출하는가?
3. 401 Unauthorized를 반환하는가?

**Backend 예상 구조** (참고):
```python
@api.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required()  # JWT 검증
def submit_job():
    # JWT에서 사용자 정보 추출
    current_user = get_jwt_identity()

    data = request.json

    # Job 데이터에 사용자 정보 추가
    job_data = {
        'user': current_user,
        'job_name': data['jobName'],
        'partition': data['partition'],
        # ...
    }

    # Slurm sbatch 실행
    result = submit_slurm_job(job_data)

    return jsonify({
        'success': True,
        'jobId': result['job_id']
    })
```

### Step 3: 에러 처리 개선

**AuthContext에 이미 구현된 기능 활용**:
- 토큰 만료 시 자동 로그아웃
- 401 에러 시 Auth Portal로 리다이렉트

**추가 개선** (선택사항):
```typescript
try {
  const data = await apiPost<{ success: boolean; jobId: string }>(
    '/api/slurm/jobs/submit',
    submitData
  );

  if (data.success) {
    toast.success(`Job ${data.jobId} submitted successfully`);
    onSubmit();
  } else {
    toast.error('Failed to submit job');
  }
} catch (error) {
  if (error instanceof ApiError) {
    if (error.statusCode === 401) {
      toast.error('Session expired. Please login again.');
      // AuthContext가 자동으로 처리하지만 명시적 메시지 표시
      setTimeout(() => {
        window.location.href = '/';
      }, 2000);
    } else if (error.statusCode === 403) {
      toast.error('You do not have permission to submit jobs');
    } else {
      toast.error(error.message);
    }
  } else {
    toast.error('An unexpected error occurred');
  }
}
```

---

## 🔍 추가 확인 사항

### 1. **다른 Job API들도 확인**

JobManagement에서 사용하는 다른 API들:

```typescript
// Job 목록 조회
const jobs = await apiGet<SlurmJob[]>(API_ENDPOINTS.jobs);  // ✅ JWT 포함

// Job 취소
await apiPost(API_ENDPOINTS.jobCancel(jobId));  // ✅ JWT 포함

// Job 홀드
await apiPost(API_ENDPOINTS.jobHold(jobId));  // ✅ JWT 포함

// Job 릴리즈
await apiPost(API_ENDPOINTS.jobRelease(jobId));  // ✅ JWT 포함
```

**결론**: Job Submit만 JWT 누락, 다른 API는 모두 정상

### 2. **파티션 정보 조회**

```typescript
// JobSubmitModal에서 사용
const response = await apiGet<{
  success: boolean;
  partitions: Partition[];
  cpus_per_node: number;
}>('/api/groups/partitions');  // ✅ JWT 포함
```

**결론**: 정상

### 3. **SSHTerminal, VNCSessionManager**

```typescript
// SSH 세션 시작
const response = await fetch(`/api/ssh/sessions`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,  // ✅ JWT 포함
  },
  body: JSON.stringify(sessionData),
});
```

**결론**: 모든 세션 관리 API도 JWT 사용 중

---

## 📊 JWT 인증 일관성 현황

```
Frontend API 호출 JWT 인증 상태

Phase 1: Apptainer Images       ████████████████████ 100% ✅
  ✅ /api/v2/apptainer/images
  ✅ /api/v2/apptainer/images/{id}
  ✅ /api/v2/apptainer/scan

Phase 2: Templates               ████████████████████ 100% ✅
  ✅ /api/v2/templates
  ✅ /api/v2/templates/{id}
  ✅ /api/v2/templates/scan

Phase 3: File Upload             ████████████████████ 100% ✅
  ✅ /api/v2/files/upload/init
  ✅ /api/v2/files/upload/chunk
  ✅ /api/v2/files/upload/complete

Job Management APIs              ████████████████░░░░  80% ⚠️
  ✅ /api/slurm/jobs (GET)
  ✅ /api/slurm/jobs/{id}/cancel
  ✅ /api/slurm/jobs/{id}/hold
  ✅ /api/slurm/jobs/{id}/release
  ❌ /api/slurm/jobs/submit       ← 수정 필요!

SSH/VNC Sessions                 ████████████████████ 100% ✅
  ✅ /api/ssh/sessions
  ✅ /api/vnc/sessions

Reports & Dashboard              ████████████████████ 100% ✅
  ✅ /api/reports/*
  ✅ /api/metrics/*

───────────────────────────────────────────────
전체 일관성:                      ████████████████████  95%
```

---

## 🚀 실행 계획

### Phase 1: 코드 수정 (15분)

1. **JobManagement.tsx 수정**
   - Line 739-743: fetch()를 apiPost()로 변경
   - 에러 처리 개선
   - 타입 정의 추가

2. **테스트**
   - 빌드 확인
   - TypeScript 에러 없는지 확인

### Phase 2: Backend 확인 (선택사항)

1. **Backend API 코드 확인**
   - `/api/slurm/jobs/submit` 엔드포인트
   - JWT 검증 데코레이터 (@jwt_required)
   - 사용자 정보 추출 로직

2. **테스트**
   - JWT 없이 요청 → 401 확인
   - JWT 포함 요청 → 200 확인
   - 만료된 JWT → 401 확인

### Phase 3: 통합 테스트 (10분)

1. **Job Submit 플로우 테스트**
   - 로그인 → Dashboard → Job Submit
   - Template 선택
   - Apptainer 이미지 선택
   - 파일 업로드
   - Job Submit → 성공 확인

2. **토큰 만료 시나리오**
   - 토큰 만료 후 Job Submit
   - 401 에러 처리 확인
   - Auth Portal 리다이렉트 확인

### Phase 4: 문서화 (5분)

1. **PHASE_1_2_3_INTEGRATION_COMPLETE.md 업데이트**
   - JWT 인증 섹션 추가
   - 보안 고려사항 문서화

---

## 🔒 보안 고려사항

### 1. **JWT 저장**
- ✅ localStorage 사용 (현재 구현)
- 대안: httpOnly cookie (더 안전하지만 Backend 변경 필요)

### 2. **토큰 만료 처리**
- ✅ 자동 체크 (1분마다)
- ✅ 401 에러 시 자동 로그아웃
- 개선: Refresh token 구현 (선택사항)

### 3. **HTTPS 사용**
- 프로덕션 환경에서 필수
- JWT를 평문으로 전송하므로 HTTPS 필수

### 4. **CSRF 방어**
- JWT는 CSRF에 안전 (Cookie 미사용)
- Authorization 헤더 사용으로 자동 방어

---

## 📝 다음 단계

### 즉시 수정 필요 (Critical)
1. ✅ JobManagement.tsx에서 Job Submit API를 apiPost()로 변경
2. ✅ 에러 처리 개선
3. ✅ 빌드 및 테스트

### 중요 (Important)
4. Backend API JWT 검증 확인
5. 통합 테스트 수행
6. 문서 업데이트

### 선택사항 (Optional)
7. Refresh token 구현
8. httpOnly cookie 전환
9. 로그인 페이지 개선

---

## 🎯 예상 결과

### 수정 후
```
✅ 모든 API가 JWT 인증 사용
✅ 일관된 에러 처리
✅ 보안 강화
✅ 사용자 추적 가능
✅ 권한 기반 접근 제어
```

### 사용자 경험
```
로그인 → JWT 발급 → Dashboard 접근
  ↓
Job Submit
  ├─ Template 선택 (JWT 포함)
  ├─ Apptainer 선택 (JWT 포함)
  ├─ 파일 업로드 (JWT 포함)
  └─ Job Submit (JWT 포함) ← 수정!
      ↓
      성공 → Job ID 반환
      실패 (401) → Auth Portal 리다이렉트
```

---

## 📚 참고 문서

- [api.ts](frontend_3010/src/utils/api.ts) - API 유틸리티
- [AuthContext.tsx](frontend_3010/src/contexts/AuthContext.tsx) - 인증 컨텍스트
- [useTemplates.ts](frontend_3010/src/hooks/useTemplates.ts) - JWT 패턴 참고
- [ChunkUploader.ts](frontend_3010/src/utils/ChunkUploader.ts) - JWT 패턴 참고

---

## 🎉 결론

**핵심 문제**: Job Submit API만 JWT 인증이 누락됨

**해결 방안**: `fetch()` 대신 `apiPost()` 사용

**영향**: 최소한 (단 5줄 변경으로 해결)

**효과**: 전체 API 호출이 JWT 인증으로 일관성 확보

이 계획을 실행하면 전체 시스템이 **100% JWT 인증**으로 통합됩니다! 🚀
