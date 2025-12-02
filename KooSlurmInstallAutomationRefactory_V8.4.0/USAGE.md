# HPC Cluster 웹 서비스 사용 가이드

## 📋 개요

이 문서는 HPC Cluster 웹 서비스의 시작, 중지 및 관리 방법을 설명합니다.

## 🚀 서비스 시작

### 전체 시스템 시작

프로젝트 루트 디렉토리에서:

```bash
./start.sh
```

이 명령은 다음 작업을 자동으로 수행합니다:

1. **프론트엔드 빌드** (Dashboard, VNC Service, CAE Frontend)
2. **기존 서비스 종료** (포트 충돌 방지)
3. **Redis 확인**
4. **SAML-IdP 시작**
5. **Auth Backend/Frontend 시작**
6. **Dashboard Backend + WebSocket 시작**
7. **Backend 설정 확인** (MOCK_MODE=false 자동 설정)
8. **CAE Services 시작**

### 시작 확인

```bash
cd dashboard
./test_startup.sh
```

모든 서비스가 정상적으로 시작되었는지 확인합니다.

## 🛑 서비스 중지

### 전체 시스템 중지

프로젝트 루트 디렉토리에서:

```bash
./stop.sh
```

이 명령은 다음 작업을 자동으로 수행합니다:

1. **SSH 터널 정리** (VNC 외부 접속용 터널)
2. **Phase 1 종료** (Auth Portal)
3. **Phase 2-4 종료** (Dashboard, WebSocket)
4. **VNC Service 종료**
5. **CAE Services 종료**
6. **남은 프로세스 정리**

## 🌐 접속 정보

### 사용자 접속 URL (Nginx Reverse Proxy)

- **메인 포털**: http://110.15.177.120/
- **Dashboard**: http://110.15.177.120/dashboard/
- **VNC Service**: http://110.15.177.120/vnc/
- **CAE Frontend**: http://110.15.177.120/cae/

### Backend API (로컬 접속)

- **Auth Backend**: http://localhost:4430
- **Dashboard API**: http://localhost:5010
- **WebSocket**: ws://localhost:5011/ws
- **CAE Backend**: http://localhost:5000
- **CAE Automation**: http://localhost:5001

## 🔧 개별 스크립트

### 프론트엔드만 다시 빌드

```bash
cd dashboard
./build_all_frontends.sh
```

### 상태 확인

```bash
cd dashboard
./test_startup.sh
```

## 📝 주요 기능

### VNC 원격 데스크톱

1. VNC Service 페이지 접속
2. "새 세션 시작" 클릭
3. 이미지 선택 (GNOME Desktop 등)
4. 해상도, 시간, GPU 설정
5. "생성" 클릭
6. 세션이 RUNNING 상태가 되면 "원격 접속" 버튼 활성화
7. 외부에서도 접속 가능 (SSH 터널 자동 생성)

### Job Management

- 실시간 Slurm job 모니터링
- Job 취소/일시정지/재개 기능
- RUNNING 및 PENDING 상태 job 관리 가능

## ⚙️ 설정

### MOCK_MODE

- **프로덕션**: `MOCK_MODE=false` (자동 설정됨)
- **개발/테스트**: 수동으로 `true`로 변경 가능

설정 파일: `dashboard/backend_5010/.env`

### VNC 외부 접속

SSH 터널이 자동으로 생성되어 외부 IP로 접속 가능:

```
http://110.15.177.120:[동적포트]/vnc.html
```

포트는 VNC 세션 생성 시 자동 할당됩니다.

## 🐛 트러블슈팅

### 서비스가 시작되지 않을 때

1. Redis 확인:
   ```bash
   sudo systemctl status redis-server
   sudo systemctl start redis-server
   ```

2. 포트 충돌 확인:
   ```bash
   lsof -ti:5010  # Dashboard API
   lsof -ti:5011  # WebSocket
   ```

3. 로그 확인:
   ```bash
   tail -f /tmp/dashboard_backend_5010.log
   tail -f /tmp/websocket_5011.log
   ```

### VNC 접속이 안 될 때

1. SSH 터널 확인:
   ```bash
   ps aux | grep "ssh.*-L.*localhost"
   netstat -tlnp | grep :6987  # 예시 포트
   ```

2. Slurm job 상태 확인:
   ```bash
   squeue -u $USER
   ```

3. VNC 프로세스 확인 (compute node에서):
   ```bash
   ps aux | grep vnc
   ps aux | grep websockify
   ```

### 빌드 실패 시

TypeScript 에러는 무시하고 esbuild로 빌드됩니다.
완전 초기화가 필요한 경우:

```bash
cd dashboard/frontend_3010
rm -rf node_modules dist
npm install
npx vite build
```

## 📊 시스템 요구사항

- **Redis**: 필수 (세션 관리)
- **Slurm**: 필수 (job 스케줄링)
- **Nginx**: 필수 (리버스 프록시)
- **Node.js**: 프론트엔드 빌드용
- **Python 3**: 백엔드 서비스

## 🔄 업데이트 후 재시작

코드 변경 후:

```bash
./stop.sh
./start.sh
```

프론트엔드만 변경 시:

```bash
cd dashboard
./build_all_frontends.sh
# Nginx가 자동으로 새 파일 제공
```

## 📞 지원

문제 발생 시 로그 파일과 함께 문의:

- `/tmp/dashboard_backend_5010.log`
- `/tmp/websocket_5011.log`
- `/tmp/cae_backend_5000.log`
- `/tmp/cae_automation_5001.log`
