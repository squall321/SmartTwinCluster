# 시스템 성능 분석 및 최적화 계획

**작성일**: 2025-12-06
**분석 대상**: 전체 Dashboard 시스템

---

## 1. 현재 상태 분석

### 📊 리소스 사용 현황

#### A. Node.js Dependencies (node_modules)
```
1.4G  - kooCAEWeb_5173 (CAE Frontend)
590M  - frontend_3010 (Dashboard Frontend)
322M  - moonlight_frontend_8003 (Moonlight Frontend)
114M  - auth_portal_4431
113M  - vnc_service_8002
109M  - app_5174

총합: ~2.6GB node_modules
```

**문제점**:
- CAE Frontend가 1.4GB로 과도하게 큼 (3D 시각화 라이브러리)
- 중복 의존성 가능성 (React, MUI 등)
- 개발 의존성이 프로덕션 빌드에 포함될 가능성

#### B. Backend Worker 설정

| 서비스 | Workers | Threads | Timeout | Max Requests |
|--------|---------|---------|---------|--------------|
| Auth Portal (4430) | 2 | 2 | 120s | 1000 |
| Dashboard Backend (5010) | 4 | 2 | 120s | 1000 |
| CAE Backend (5000) | 4 | 2 | 300s | 500 |
| CAE Automation (5001) | 4 | 2 | 300s | - |

**현황**:
- ✅ Gunicorn worker_tmp_dir = /dev/shm (메모리 기반)
- ✅ preload_app = True (메모리 효율성)
- ⚠️ Max requests 값이 적절하지 않을 수 있음

#### C. 로그 파일 크기
```
656K - backend_5010/logs/backend.log
628K - auth_portal_4430/logs/auth_portal.log
376K - vnc_sandbox/build.log
```

**문제점**:
- 로그 로테이션 설정 필요
- 디스크 I/O 병목 가능성

---

## 2. 성능 병목 지점

### 🔴 Critical (즉시 개선 필요)

#### 1. Frontend 빌드 크기
- **문제**: CAE Frontend 1.4GB node_modules
- **영향**: 빌드 시간 증가, CI/CD 느림
- **해결**: Tree-shaking, Code splitting, 의존성 최적화

#### 2. 정적 파일 캐싱 부재
- **문제**: Nginx에 캐싱 헤더 미설정
- **영향**: 불필요한 네트워크 트래픽
- **해결**: Cache-Control 헤더 설정

#### 3. API 응답 캐싱 없음
- **문제**: Slurm API 호출마다 실시간 조회
- **영향**: 불필요한 Slurm 부하
- **해결**: Redis 캐싱 전략

### 🟡 Medium (개선 권장)

#### 4. Vite 빌드 최적화 부족
- **문제**: manualChunks 미설정
- **영향**: 초기 로딩 시간
- **해결**: Vendor chunk 분리

#### 5. 이미지 최적화 부재
- **문제**: 원본 이미지 그대로 제공
- **영향**: 페이지 로딩 속도
- **해결**: WebP 변환, lazy loading

### 🟢 Low (장기 개선)

#### 6. Database 인덱스 최적화
- **문제**: 느린 쿼리 존재 가능성
- **영향**: API 응답 시간
- **해결**: 쿼리 프로파일링

---

## 3. 최적화 계획

### Phase 1: Frontend 최적화 (즉시 적용 가능)

#### A. Vite 빌드 최적화

**대상 파일**:
- `frontend_3010/vite.config.ts`
- `kooCAEWeb_5173/vite.config.ts`
- `moonlight_frontend_8003/vite.config.ts`

**변경 사항**:
```typescript
build: {
  rollupOptions: {
    output: {
      manualChunks: {
        'vendor-react': ['react', 'react-dom', 'react-router-dom'],
        'vendor-mui': ['@mui/material', '@mui/icons-material'],
        'vendor-utils': ['axios', 'date-fns', 'lodash']
      }
    }
  },
  chunkSizeWarningLimit: 1000,
  sourcemap: false,  // 프로덕션에서 비활성화
  minify: 'terser',
  terserOptions: {
    compress: {
      drop_console: true,  // console.log 제거
      drop_debugger: true
    }
  }
}
```

**기대 효과**:
- 초기 로딩 시간 30-50% 감소
- 캐시 효율성 증가 (vendor 파일 재사용)

#### B. 의존성 최적화

**kooCAEWeb_5173 분석 필요**:
```bash
npx depcheck  # 미사용 의존성 찾기
npx webpack-bundle-analyzer  # 번들 크기 분석
```

**가능한 개선**:
- 사용하지 않는 3D 라이브러리 제거
- Three.js → lighter alternative 검토
- Dynamic import로 필요 시에만 로드

#### C. TypeScript 빌드 최적화

**tsconfig.json 개선**:
```json
{
  "compilerOptions": {
    "incremental": true,
    "tsBuildInfoFile": ".tsbuildinfo",
    "skipLibCheck": true,
    "noEmit": false
  }
}
```

---

### Phase 2: Backend 최적화

#### A. Gunicorn Worker 튜닝

**현재 문제**:
- Worker 수 고정 (4 workers)
- CPU 코어 수에 따라 조정 필요

**최적화 공식**:
```python
workers = min((multiprocessing.cpu_count() * 2) + 1, 8)
# 예: 4 cores → 9 workers (최대 8로 제한)
```

**권장 설정**:
```python
# backend_5010/gunicorn_config.py
workers = min((multiprocessing.cpu_count() * 2) + 1, 8)
threads = 4  # 2 → 4로 증가
worker_class = "gthread"
max_requests = 2000  # 1000 → 2000 (재시작 빈도 감소)
max_requests_jitter = 100
```

**기대 효과**:
- 동시 요청 처리 능력 2배 증가
- Worker 재시작 빈도 감소

#### B. Redis 캐싱 전략

**캐싱 대상**:
1. Slurm 노드 상태 (TTL: 5초)
2. 작업 목록 (TTL: 3초)
3. 사용자 권한 (TTL: 60초)
4. 클러스터 통계 (TTL: 10초)

**구현 예시**:
```python
from functools import wraps
import redis
import json

redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

def cache(ttl=60, key_prefix='api'):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            cache_key = f"{key_prefix}:{func.__name__}:{hash(str(args) + str(kwargs))}"

            # 캐시 확인
            cached = redis_client.get(cache_key)
            if cached:
                return json.loads(cached)

            # 실행 및 캐싱
            result = func(*args, **kwargs)
            redis_client.setex(cache_key, ttl, json.dumps(result))
            return result
        return wrapper
    return decorator

@cache(ttl=5, key_prefix='slurm')
def get_node_status():
    # Slurm API 호출
    pass
```

**기대 효과**:
- API 응답 시간 80-95% 감소
- Slurm 부하 90% 감소

---

### Phase 3: Nginx 최적화

#### A. 정적 파일 캐싱

**nginx.conf 추가**:
```nginx
# /etc/nginx/conf.d/auth-portal.conf

# Gzip 압축
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml text/javascript
           application/javascript application/xml+rss
           application/json image/svg+xml;

# 정적 파일 캐싱
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# HTML 파일 (캐싱 안 함)
location ~* \.html$ {
    expires -1;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

# API 응답 캐싱 (선택적)
proxy_cache_path /var/cache/nginx/api levels=1:2 keys_zone=api_cache:10m max_size=100m inactive=60s;

location /api/nodes {
    proxy_cache api_cache;
    proxy_cache_valid 200 5s;
    proxy_cache_key "$request_uri";
    add_header X-Cache-Status $upstream_cache_status;
    proxy_pass http://backend_5010;
}
```

**기대 효과**:
- 정적 파일 전송 속도 10배 증가
- 대역폭 사용량 60-70% 감소

#### B. HTTP/2 활성화

```nginx
listen 443 ssl http2;
listen [::]:443 ssl http2;
```

**기대 효과**:
- 다중 요청 병렬 처리
- 헤더 압축으로 오버헤드 감소

---

### Phase 4: Database 최적화

#### A. Redis 설정 튜닝

**redis.conf 최적화**:
```conf
# 메모리 설정
maxmemory 2gb
maxmemory-policy allkeys-lru

# 성능 설정
save ""  # RDB 스냅샷 비활성화 (AOF 사용)
appendonly yes
appendfsync everysec

# 네트워크
tcp-backlog 511
timeout 300
```

#### B. MariaDB 쿼리 최적화

**인덱스 추가**:
```sql
-- 사용자 조회 최적화
CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_email ON users(email);

-- 작업 조회 최적화
CREATE INDEX idx_job_user_status ON jobs(user_id, status);
CREATE INDEX idx_job_created_at ON jobs(created_at DESC);
```

---

## 4. 성능 측정 기준

### Before (현재 추정치)

| 메트릭 | 값 |
|--------|-----|
| Frontend 초기 로딩 | 3-5초 |
| API 응답 시간 (평균) | 200-500ms |
| Slurm 노드 조회 | 100-200ms |
| Dashboard 빌드 시간 | 60-90초 |
| CAE Frontend 빌드 | 120-180초 |

### After (목표)

| 메트릭 | 값 | 개선율 |
|--------|-----|--------|
| Frontend 초기 로딩 | 1-2초 | 60% ↓ |
| API 응답 시간 (평균) | 20-50ms | 90% ↓ |
| Slurm 노드 조회 | 5-10ms | 95% ↓ |
| Dashboard 빌드 시간 | 30-45초 | 50% ↓ |
| CAE Frontend 빌드 | 60-90초 | 50% ↓ |

---

## 5. 우선순위 로드맵

### Week 1: Quick Wins
- [x] 성능 분석 완료
- [ ] Vite 빌드 설정 최적화 (모든 frontend)
- [ ] Nginx 정적 파일 캐싱 설정
- [ ] console.log 제거 (프로덕션 빌드)

### Week 2: Backend 캐싱
- [ ] Redis 캐싱 데코레이터 구현
- [ ] Slurm API 캐싱 적용
- [ ] 사용자 권한 캐싱 적용
- [ ] API 응답 시간 모니터링

### Week 3: Advanced 최적화
- [ ] Gunicorn worker 자동 튜닝
- [ ] Database 인덱스 최적화
- [ ] HTTP/2 활성화
- [ ] 로그 로테이션 설정

### Week 4: 측정 및 검증
- [ ] 성능 벤치마크 실행
- [ ] 부하 테스트 (Apache Bench, k6)
- [ ] 모니터링 대시보드 구축
- [ ] 최종 리포트 작성

---

## 6. 도구 및 모니터링

### 성능 측정 도구
```bash
# Frontend 빌드 분석
npx vite-bundle-visualizer

# API 성능 테스트
ab -n 1000 -c 10 http://localhost:5010/api/nodes

# 부하 테스트 (k6)
k6 run load_test.js

# Redis 모니터링
redis-cli --latency
redis-cli info stats
```

### 실시간 모니터링
- **Prometheus**: 이미 포트 9090에서 실행 중
- **Node Exporter**: 포트 9100에서 실행 중
- **Grafana**: 추가 권장 (시각화)

---

## 7. 예상 비용/효과

### 개발 시간
- Phase 1 (Frontend): 4-6 시간
- Phase 2 (Backend): 6-8 시간
- Phase 3 (Nginx): 2-3 시간
- Phase 4 (Database): 3-4 시간

**총 개발 시간**: 15-21 시간

### 기대 효과
- **사용자 경험**: 로딩 속도 60% 개선
- **서버 비용**: CPU/메모리 사용량 30-40% 감소
- **확장성**: 동시 사용자 수 2-3배 증가 가능
- **안정성**: API 응답 시간 안정화

---

## 결론

현재 시스템은 **기능적으로 완성**되었으나, **성능 최적화가 필요**합니다.

**즉시 적용 가능한 개선**:
1. ✅ Vite 빌드 설정 (manualChunks, terser)
2. ✅ Nginx 캐싱 헤더
3. ✅ Redis 캐싱 전략

**장기적 개선**:
4. Gunicorn worker 자동 튜닝
5. Database 인덱스 최적화
6. 모니터링 대시보드 구축

다음 단계: **Phase 1 Frontend 최적화 시작**
