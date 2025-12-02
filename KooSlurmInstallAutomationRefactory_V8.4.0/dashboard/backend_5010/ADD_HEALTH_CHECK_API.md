# Health Check API를 app.py에 추가하는 가이드

## 수정 위치: app.py

### 1. Import 섹션에 추가 (약 100번째 줄 근처)

```python
# v3.4 신규 기능 Blueprint 임포트
from dashboard_api import dashboard_bp

# 🆕 v3.5 Health Check API 임포트
from health_check_api import health_bp
```

### 2. Blueprint 등록 섹션에 추가 (약 130번째 줄 근처)

```python
# 파일 업로드 API 등록
app.register_blueprint(upload_bp)

# 🆕 v3.5 Health Check API 등록
app.register_blueprint(health_bp)
```

### 3. API 목록 출력 부분에 추가 (main 함수의 print 섹션)

```python
    print("📊 v3.4.0 Dashboard API:")
    print("  GET  /api/reports/dashboard/resources")
    print("  GET  /api/reports/dashboard/top-users?limit=10")
    print("  GET  /api/reports/dashboard/job-status")
    print("  GET  /api/reports/dashboard/cost-trends?period=week")
    print("  GET  /api/reports/dashboard/health")
    print("")
    print("🏥 v3.5.0 Health Check API:")  # 🆕 추가
    print("  GET  /api/health/status")
    print("  GET  /api/health/summary")
    print("  GET  /api/health/endpoints")
    print("  POST /api/health/auto-heal")
    print("")
```

## 완료 후 확인

```bash
# 백엔드 재시작
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010
./stop.sh
./start.sh

# Health Check API 테스트
curl http://localhost:5010/api/health/status
curl http://localhost:5010/api/health/summary
```
