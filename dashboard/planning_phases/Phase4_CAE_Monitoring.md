# Phase 4: CAE 통합 및 모니터링

**기간**: 1주 (5일)
**목표**: CAE 서비스 JWT 통합 + Prometheus/Grafana 대시보드 구축
**선행 조건**: Phase 1, 2 완료
**담당자**: Backend 개발자 + DevOps

---

## Day 1-2: CAE 서비스 JWT 통합

### kooCAEWebServer_5000 수정
```python
# kooCAEWebServer_5000에 middleware/ 복사
cp -r backend_5010/middleware kooCAEWebServer_5000/

# app.py에 JWT 미들웨어 적용
from middleware.jwt_middleware import jwt_required, permission_required

@app.route('/api/workflow/execute', methods=['POST'])
@jwt_required
@permission_required(['cae.execute'])
def execute_workflow():
    user = g.user
    # 기존 워크플로우 실행 로직...
```

### kooCAEWeb_5173 수정
```typescript
// src/utils/jwt.ts 복사
// src/api/client.ts Axios 인터셉터 추가
// App.tsx에서 토큰 처리

// 동일한 패턴으로 frontend_3010과 동일하게 구현
```

---

## Day 3-4: Prometheus 메트릭 추가

### Auth Portal 메트릭
```python
# auth_portal_4430/metrics.py
from prometheus_client import Counter, Histogram, generate_latest

auth_saml_requests = Counter('auth_saml_requests_total', 'SAML requests', ['status'])
auth_jwt_issued = Counter('auth_jwt_issued_total', 'JWT tokens issued')
auth_jwt_failures = Counter('auth_jwt_validation_failures_total', 'JWT validation failures')

@app.route('/metrics')
def metrics():
    return generate_latest()
```

### VNC 메트릭
```python
# backend_5010/metrics.py 확장
vnc_sessions_total = Gauge('vnc_sessions_total', 'Active VNC sessions')
vnc_sessions_created = Counter('vnc_sessions_created_total', 'Created sessions')
vnc_sessions_failed = Counter('vnc_sessions_failed_total', 'Failed sessions')
```

### Prometheus 설정
```yaml
# prometheus_9090/prometheus.yml
scrape_configs:
  - job_name: 'auth-portal'
    static_configs:
      - targets: ['localhost:4430']

  - job_name: 'dashboard-backend'
    static_configs:
      - targets: ['localhost:5010']
```

---

## Day 5: Grafana 대시보드

### VNC Sessions 대시보드
- Panel 1: 현재 활성 세션 수 (Gauge)
- Panel 2: 시간별 세션 생성 (Time Series)
- Panel 3: GPU 사용률 (Time Series)

### Auth System 대시보드
- Panel 1: 로그인 성공/실패율 (Pie Chart)
- Panel 2: JWT 발급 수 (Time Series)

---

**Phase 4 완료!**
