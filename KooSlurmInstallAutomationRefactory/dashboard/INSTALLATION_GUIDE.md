# 🚀 Dashboard 설치 및 실행 가이드

## 📋 빠른 시작

### 1. 전체 환경 설정 (최초 1회만)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# setup_all.sh에 실행 권한 부여
chmod +x setup_all.sh

# 전체 환경 설정 (자동으로 모든 스크립트 권한 부여)
./setup_all.sh
```

**setup_all.sh가 자동으로 수행하는 작업**:
- ✅ **모든 스크립트 실행 권한 부여** (start.sh, stop.sh 등)
- ✅ Backend venv 생성 및 패키지 설치
- ✅ WebSocket venv 생성 및 패키지 설치
- ✅ Frontend npm 패키지 설치
- ✅ 데이터베이스 초기화

---

### 2. 서버 시작

#### Mock Mode (테스트/개발)
```bash
./start_all_mock.sh
```
- 🎭 샘플 데이터 사용
- ✅ Slurm 없어도 작동
- ✅ 안전한 테스트

#### Production Mode (실제 운영)
```bash
./start_all.sh
```
- 🚀 실제 Slurm 명령 실행
- ⚠️ Slurm 설치 필요
- ✅ 실제 노드 관리

---

### 3. 접속

브라우저에서 다음 주소로 접속:
```
http://localhost:3010
```

Node Management 탭에서 모드 확인:
- Mock Mode: 🎭 **MOCK MODE** (노란색)
- Production Mode: 🚀 **PRODUCTION** (초록색)

---

### 4. 서버 종료

```bash
./stop_all.sh
```

---

## 📦 상세 설정 과정

### setup_all.sh 실행 과정

```
==========================================
🚀 Dashboard 전체 환경 설정
==========================================

[0/4] 모든 스크립트 실행 권한 부여...

✓ 최상위 스크립트 (start_all.sh, stop_all.sh 등)
✓ Backend 스크립트
✓ WebSocket 스크립트
✓ Frontend 스크립트
✓ Prometheus 스크립트
✓ Node Exporter 스크립트

✅ 모든 스크립트 실행 권한 부여 완료

✓ Python: Python 3.x.x
✓ Node.js: v18.x.x

[1/4] Backend 설정 중...
✅ Backend 설정 완료

[2/4] WebSocket 설정 중...
✅ WebSocket 설정 완료

[3/4] Frontend 설정 중...
✅ Frontend 설정 완료

[참고] Prometheus와 Node Exporter는 바이너리 실행
  - prometheus_9090/: 이미 준비됨
  - node_exporter_9100/: 이미 준비됨

[4/4] 데이터베이스 초기화...
✅ 데이터베이스 초기화 완료

==========================================
🎉 전체 환경 설정 완료!
==========================================

다음 단계:
  1. 전체 서버 시작: ./start_all.sh
  2. 전체 서버 중지: ./stop_all.sh
  3. 서비스 상태 확인: ./check_services.sh
```

---

## 🔑 실행 권한이 자동으로 부여되는 스크립트

### 최상위 디렉토리
- `setup_all.sh` ← 이것만 수동으로 chmod 필요
- `start_all.sh` ✅ 자동
- `start_all_mock.sh` ✅ 자동
- `stop_all.sh` ✅ 자동
- `check_services.sh` ✅ 자동
- `toggle_mock_mode.sh` ✅ 자동

### backend_5010/
- `setup.sh` ✅ 자동
- `start.sh` ✅ 자동
- `stop.sh` ✅ 자동
- `restart_backend.sh` ✅ 자동
- `restart_node_api.sh` ✅ 자동
- `switch_mode.sh` ✅ 자동
- `test_api.sh` ✅ 자동
- `debug_api.sh` ✅ 자동

### websocket_5011/
- `setup.sh` ✅ 자동
- `start.sh` ✅ 자동
- `stop.sh` ✅ 자동

### frontend_3010/
- `setup.sh` ✅ 자동
- `start.sh` ✅ 자동
- `stop.sh` ✅ 자동

### prometheus_9090/
- `start.sh` ✅ 자동
- `stop.sh` ✅ 자동

### node_exporter_9100/
- `start.sh` ✅ 자동
- `stop.sh` ✅ 자동

---

## 🔄 모드 전환

### 전체 모드 전환 (권장)

```bash
# Production → Mock
./stop_all.sh
./start_all_mock.sh

# Mock → Production
./stop_all.sh
./start_all.sh
```

### Backend만 모드 전환

```bash
cd backend_5010
./switch_mode.sh
```

---

## 🔍 상태 확인

### 전체 서비스 확인
```bash
./check_services.sh
```

### API로 모드 확인
```bash
curl http://localhost:5010/api/nodes | jq '.mode'
```

### 로그 확인
```bash
# Backend 로그
tail -f backend_5010/logs/backend.log

# WebSocket 로그
tail -f websocket_5011/websocket.log

# Frontend 로그
tail -f frontend_3010/frontend.log
```

---

## 🛠️ 문제 해결

### 문제: "./start_all.sh: Permission denied"

**원인**: setup_all.sh를 실행하지 않았거나 실패함

**해결**:
```bash
# setup_all.sh 실행 권한 부여
chmod +x setup_all.sh

# 다시 실행
./setup_all.sh
```

### 문제: 일부 스크립트만 권한 없음

**해결**: 수동으로 권한 부여
```bash
# 모든 스크립트에 일괄 권한 부여
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### 문제: Python/Node.js 버전 에러

**해결**:
```bash
# Python 확인
python3 --version
# 또는
python3.12 --version

# Node.js 확인
node --version

# 버전이 맞지 않으면 설치
# Ubuntu/Debian: sudo apt install python3 nodejs npm
# CentOS/RHEL: sudo yum install python3 nodejs npm
```

### 문제: 포트 충돌

**해결**: start_all.sh가 자동으로 포트 정리
```bash
./stop_all.sh
sleep 3
./start_all.sh
```

---

## 📚 관련 문서

- **Mock/Production Mode 가이드**: `MOCK_PRODUCTION_MODE_GUIDE.md`
- **Phase 1-2 완료 문서**: `PHASE1_2_NODE_MANAGEMENT_COMPLETE.md`
- **빠른 시작**: `QUICK_START_PHASE1_2.md`
- **로드맵**: `ROADMAP.md`

---

## ✅ 체크리스트

### 초기 설정
- [ ] setup_all.sh 실행 권한 부여
- [ ] setup_all.sh 실행
- [ ] 모든 스크립트 권한 자동 부여 확인
- [ ] Python 3.x 설치 확인
- [ ] Node.js 설치 확인

### 서버 시작
- [ ] Mock 또는 Production 모드 선택
- [ ] start_all.sh 또는 start_all_mock.sh 실행
- [ ] 브라우저에서 접속 (http://localhost:3010)
- [ ] Mode Badge 확인

### 기능 확인
- [ ] Node Management 탭 접근
- [ ] 노드 목록 표시
- [ ] Drain/Resume 버튼 작동
- [ ] Mode Badge 색상 확인

---

## 🎯 권장 워크플로우

### 개발 환경
```bash
# 1. 최초 설정 (1회만)
chmod +x setup_all.sh
./setup_all.sh

# 2. Mock Mode로 개발
./start_all_mock.sh

# 3. 개발 완료 후 테스트
./stop_all.sh
./start_all.sh  # Production Mode로 최종 확인

# 4. 종료
./stop_all.sh
```

### 운영 환경
```bash
# 1. 최초 설정 (1회만)
chmod +x setup_all.sh
./setup_all.sh

# 2. Production Mode로 시작
./start_all.sh

# 3. 정기적인 로그 확인
tail -f backend_5010/logs/backend.log

# 4. 유지보수 시 종료
./stop_all.sh
```

---

## 💡 팁

### 빠른 재시작
```bash
# 전체 재시작
./stop_all.sh && sleep 2 && ./start_all.sh

# Backend만 재시작
cd backend_5010
./stop.sh && ./start.sh
```

### 로그 실시간 모니터링
```bash
# 여러 터미널 창에서 각각 실행
tail -f backend_5010/logs/backend.log
tail -f websocket_5011/websocket.log
tail -f frontend_3010/frontend.log
```

### 포트 사용 확인
```bash
# 사용 중인 포트 확인
lsof -i :3010,5010,5011,9100,9090

# 또는
netstat -tlnp | grep -E "3010|5010|5011|9100|9090"
```

---

**작성일**: 2025-10-10  
**버전**: 2.0  
**업데이트**: 자동 실행 권한 부여 추가
