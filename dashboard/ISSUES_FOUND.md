# 성능 최적화 코드 검증 - 발견된 문제점

**검증 일시**: 2025-12-06
**검증 범위**: Frontend Vite 설정, Backend Redis 캐싱, Nginx 설정

---

## 🔴 Critical Issues (즉시 수정 필요)

### 1. Vite manualChunks 의존성 불일치

**파일**: `frontend_3010/vite.config.ts`

**문제**:
```typescript
manualChunks: {
  'vendor-mui': ['@mui/material', '@mui/icons-material', '@emotion/react', '@emotion/styled'],
  // ...
}
```

**실제 상황**:
- `frontend_3010/package.json`에 **MUI 의존성이 없음**
- `@mui/material`, `@emotion/react` 등이 설치되지 않음
- 빌드 시 에러 발생 가능

**영향**: 빌드 실패

**해결 방법**: manualChunks에서 존재하지 않는 패키지 제거

---

### 2. CAE Frontend lodash 의존성

**파일**: `kooCAEWeb_5173/vite.config.ts`

**문제**:
```typescript
manualChunks: {
  'vendor-utils': ['axios', 'lodash']
}
```

**실제 상황**:
- `package.json`에 `lodash` 직접 의존성 없음
- `lodash.debounce`만 설치됨 (다른 패키지)
- `lodash`는 transitive dependency로만 존재

**영향**: 빌드 경고 또는 청크 생성 실패

**해결 방법**: `lodash` 제거 또는 실제 사용 중인 패키지로 변경

---

### 3. Redis Python 패키지 누락

**파일**: `backend_5010/requirements.txt`

**문제**: `redis` 패키지가 requirements.txt에 없음

**실제 상황**:
- `cache_decorator.py`에서 `import redis` 사용
- 시스템에 우연히 설치되어 있지만, requirements.txt에 명시 안 됨
- 새 환경에서 설치 시 실패

**영향**: 배포 환경에서 import 실패

**해결 방법**: `redis>=4.6.0` 추가

---

## 🟡 Medium Issues (개선 권장)

### 4. Nginx 설정 파일 실전 적용 어려움

**파일**: `nginx_performance_optimization.conf`

**문제**:
- 주석으로만 설명된 설정이 많음
- `http` 블록과 `server` 블록이 혼재
- 그대로 include 하면 에러 발생 가능

**개선 방안**:
- 실제 적용 가능한 구조로 분리
- `http_block_settings.conf`와 `server_block_settings.conf` 분리

---

### 5. Gunicorn 설정 파일명 불일치

**파일**: `gunicorn_config.optimized.py`

**문제**:
- 파일명이 `.optimized.py`로 끝남
- 적용 시 수동으로 교체 필요
- 실수로 원본 파일 사용 가능

**개선 방안**: 자동 적용 스크립트 필요

---

### 6. Cache Decorator 의존성 하드코딩

**파일**: `backend_5010/utils/cache_decorator.py`

**문제**:
```python
redis_client = redis.Redis(
    host='localhost',
    port=6379,
    # ...
)
```

**개선점**:
- 환경 변수로 설정 가능하게
- `.env` 파일 지원
- 연결 풀 사용 (성능 개선)

---

### 7. Vite Terser 설정 - 너무 공격적

**파일**: 모든 `vite.config.ts`

**문제**:
```typescript
terserOptions: {
  compress: {
    drop_console: true,
    drop_debugger: true,
    pure_funcs: ['console.log', 'console.info', 'console.debug']
  }
}
```

**우려사항**:
- `console.error`, `console.warn`도 제거할 가능성
- 프로덕션 디버깅 어려움

**개선 방안**: 환경 변수로 제어

---

## 🟢 Minor Issues (선택적 개선)

### 8. Vite 버전 차이

**발견**:
- `frontend_3010`: Vite 7.1.9
- `kooCAEWeb_5173`: Vite 6.3.5
- `moonlight_frontend_8003`: Vite 7.2.4

**영향**: 동작 차이 가능성 (미미)

**권장**: 버전 통일 (선택적)

---

### 9. TypeScript 빌드 체인

**발견**:
- Dashboard: `vite build` (tsc 별도)
- CAE: `tsc -b && vite build`
- Moonlight: `tsc -b && vite build`

**영향**: 빌드 시간 차이

**권장**: 일관성 있게 통일

---

### 10. Cache Hit Rate 모니터링 부재

**문제**: `cache_decorator.py`에서 통계 함수는 있지만, API 엔드포인트 없음

**개선**: `/api/cache/stats` 엔드포인트 추가 권장

---

## 📊 발견된 문제 요약

| 심각도 | 개수 | 즉시 수정 필요 |
|--------|------|----------------|
| Critical | 3 | ✅ Yes |
| Medium | 4 | ⚠️ 권장 |
| Minor | 3 | 선택적 |

---

## ✅ 수정 계획

### Phase 1: Critical 수정 (즉시)
1. ✅ Vite manualChunks 의존성 수정
2. ✅ requirements.txt에 redis 추가
3. ✅ CAE lodash 참조 제거

### Phase 2: Medium 개선 (1-2일)
4. ✅ Nginx 설정 실전 적용 가능하게 재구성
5. ✅ Cache decorator 환경 변수 지원
6. ✅ 자동 적용 스크립트 작성

### Phase 3: Minor 개선 (선택적)
7. Vite/TypeScript 버전 통일 검토
8. Cache stats API 엔드포인트 추가
9. 환경별 terser 설정 분리

---

다음: Critical 문제 수정 시작