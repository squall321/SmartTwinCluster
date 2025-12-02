# App Framework - Quick Reference

빠른 참조 가이드 (개발자용)

---

## 🚀 빠른 시작

### 전체 시스템 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_complete.sh
```

### 전체 시스템 종료
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./stop_complete.sh
```

### Frontend 개발 모드
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174
npm run dev
# → http://localhost:5174
```

---

## 🌐 주요 URL

| 서비스 | URL | 설명 |
|--------|-----|------|
| 메인 포털 | http://110.15.177.120/ | Auth Portal |
| Dashboard | http://110.15.177.120/dashboard/ | Dashboard UI |
| CAE | http://110.15.177.120/cae/ | CAE Frontend |
| VNC Service | http://110.15.177.120/vnc/ | VNC Service UI |
| Prometheus | http://110.15.177.120/prometheus | Metrics |

---

## 📡 API Endpoints

### App Session API

**Base URL**: `http://localhost:5000/api/app` (또는 `http://110.15.177.120/cae/api/app`)

#### 세션 생성
```bash
POST /sessions
Content-Type: application/json

{
  "app_id": "gedit",
  "user_id": "testuser"
}

Response: 201 Created
{
  "session_id": "app-session-1729756800-abc123",
  "status": "creating",
  "displayUrl": null,
  "created_at": "2025-10-24T14:30:00Z"
}
```

#### 세션 목록 조회
```bash
GET /sessions

Response: 200 OK
{
  "sessions": [
    {
      "session_id": "...",
      "app_id": "gedit",
      "status": "running",
      "displayUrl": "ws://192.168.122.252:6080",
      ...
    }
  ]
}
```

#### 세션 상세 조회
```bash
GET /sessions/:session_id

Response: 200 OK
{
  "session_id": "app-session-1729756800-abc123",
  "app_id": "gedit",
  "status": "running",
  "displayUrl": "ws://192.168.122.252:6080",
  "node": "viz-node001",
  "node_ip": "192.168.122.252",
  "vnc_port": 6080,
  ...
}
```

#### 세션 삭제
```bash
DELETE /sessions/:session_id

Response: 200 OK
{
  "message": "Session deleted successfully"
}
```

#### 세션 재시작
```bash
POST /sessions/:session_id/restart

Response: 200 OK
{
  "session_id": "...",
  "status": "creating",
  ...
}
```

#### 앱 목록 조회
```bash
GET /apps

Response: 200 OK
{
  "apps": [
    {
      "id": "gedit",
      "name": "GEdit",
      "description": "Text Editor",
      "icon": "...",
      "resources": {
        "cpus": 2,
        "memory": "2Gi",
        "partition": "viz"
      }
    }
  ]
}
```

---

## 🐧 Slurm 명령어

### Job 제출 (수동 테스트)
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/slurm_jobs

sbatch --export SESSION_ID=test-001,VNC_PORT=6080 gedit_vnc_job.sh
# Submitted batch job 181
```

### Job 상태 확인
```bash
squeue
# JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST
#   181       viz gedit_vn  koopark  R       0:05      1 viz-node001

squeue -j 181
# 특정 Job 상태 확인
```

### Job 정보 상세
```bash
scontrol show job 181
```

### Job 취소
```bash
scancel 181
```

### Job 로그 확인
```bash
cat /tmp/gedit_vnc_181.out  # stdout
cat /tmp/gedit_vnc_181.err  # stderr
```

### Job Info 파일 확인
```bash
cat /tmp/app_session_test-001.info
# JOB_ID=181
# NODE=viz-node001
# NODE_IP=192.168.122.252
# VNC_PORT=6080
# STATUS=running
```

### 파티션 상태
```bash
sinfo
# PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
# normal*      up   infinite      2   idle node[001-002]
# viz          up   infinite      1   idle viz-node001
```

### 노드 상태
```bash
scontrol show node viz-node001
```

---

## 🐳 Apptainer 명령어

### 컨테이너 빌드
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174

sudo apptainer build gedit.sif apptainer/gedit.def
```

### 컨테이너 실행 (로컬 테스트)
```bash
apptainer run gedit.sif
```

### 컨테이너 정보 확인
```bash
apptainer inspect gedit.sif
```

### 배포된 이미지 확인
```bash
# Access Node
ls -lh /opt/apptainers/apps/gedit/gedit.sif

# Viz Node
ssh viz-node001 ls -lh /opt/apptainers/apps/gedit/gedit.sif
```

### 이미지 배포
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./deploy_apptainers.sh
```

---

## 🔍 디버깅

### Backend 로그 확인

```bash
# CAE Backend (5000)
tail -f /tmp/cae_backend_5000.log

# Dashboard Backend (5010)
tail -f /tmp/dashboard_backend_5010.log

# WebSocket Server (5011)
tail -f /tmp/websocket_5011.log

# Auth Backend (4430)
tail -f /home/koopark/claude/.../auth_portal_4430/logs/backend.log
```

### 포트 확인
```bash
# 특정 포트 사용 중인 프로세스 확인
lsof -i:5000
lsof -i:6080

# 모든 리스닝 포트
netstat -tulpn | grep LISTEN

# 특정 포트만
ss -tulpn | grep :5000
```

### 프로세스 확인
```bash
# Python 프로세스
ps aux | grep python

# CAE Backend
ps aux | grep "kooCAEWebServer_5000.*app.py"

# Dashboard Backend
ps aux | grep "backend_5010.*app.py"

# Vite Dev Server
ps aux | grep vite
```

### Slurm 상태 확인
```bash
# Controller 상태
systemctl status slurmctld

# Slurmd 상태 (compute nodes)
systemctl status slurmd

# Slurm 로그
sudo tail -f /var/log/slurm/slurmctld.log
sudo tail -f /var/log/slurm/slurmd.log
```

### Nginx 상태 확인
```bash
# Nginx 상태
systemctl status nginx

# Nginx 로그
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# 설정 테스트
sudo nginx -t

# Reload (설정 변경 후)
sudo systemctl reload nginx
```

---

## 🔧 일반적인 문제 해결

### 1. Backend 시작 실패 (Python Version Mismatch)

**증상**: `ImportError: undefined symbol: PyThreadState_GetUnchecked`

**해결**:
```bash
cd kooCAEWebServer_5000
./venv/bin/python app.py  # python3이 아님!
```

### 2. Nginx 404 on /auth

**증상**: 로그인 시 404 HTML 응답

**해결**:
```bash
sudo nano /etc/nginx/sites-enabled/hpc-portal.conf
# location /auth 블록을 location / 위로 이동
sudo systemctl reload nginx
```

### 3. Prometheus 시작 실패 (Port Conflict)

**증상**: `bind: address already in use` (9090)

**해결**:
```bash
sudo snap stop prometheus
sudo snap disable prometheus
cd prometheus_9090 && ./start.sh
```

### 4. Slurm Controller Down

**증상**: `Unable to contact slurm controller`

**해결**:
```bash
sudo mkdir -p /run/slurm
sudo chown slurm:slurm /run/slurm
sudo systemctl start slurmctld
```

### 5. GEdit Job Memory Error

**증상**: `Memory specification can not be satisfied`

**해결**:
```bash
cd app_5174/slurm_jobs
nano gedit_vnc_job.sh
# #SBATCH --mem=2G  (4G에서 2G로 변경)
```

### 6. VNC 연결 실패

**증상**: noVNC 연결 타임아웃

**확인 사항**:
```bash
# 1. Job이 실행 중인지 확인
squeue

# 2. Job info 파일 존재 확인
cat /tmp/app_session_xxx.info

# 3. Viz 노드에서 websockify 실행 확인
ssh viz-node001 "ps aux | grep websockify"

# 4. 포트가 열려있는지 확인
ssh viz-node001 "lsof -i:6080"

# 5. 방화벽 확인
ssh viz-node001 "sudo iptables -L -n | grep 6080"
```

---

## 📦 파일 위치

### 주요 디렉토리

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/
├── app_5174/                          # App Framework
│   ├── src/                           # Frontend source
│   ├── apptainer/                     # Container definitions
│   ├── slurm_jobs/                    # Job templates
│   └── docs/                          # Documentation
├── kooCAEWebServer_5000/              # CAE Backend
│   ├── services/                      # AppSessionService, SlurmAppManager
│   └── venv/                          # Python 3.13
├── backend_5010/                      # Dashboard Backend
│   └── venv/                          # Python 3.12
├── auth_portal_4430/                  # Auth Backend
├── auth_portal_4431/                  # Auth Frontend
└── start_complete.sh                  # Master start script
```

### 로그 파일

```
/tmp/cae_backend_5000.log              # CAE Backend
/tmp/cae_automation_5001.log           # CAE Automation
/tmp/dashboard_backend_5010.log        # Dashboard Backend
/tmp/websocket_5011.log                # WebSocket Server
/tmp/gedit_vnc_<JOB_ID>.out            # Slurm Job stdout
/tmp/gedit_vnc_<JOB_ID>.err            # Slurm Job stderr
/tmp/app_session_<SESSION_ID>.info     # Job info
/var/log/nginx/access.log              # Nginx access
/var/log/nginx/error.log               # Nginx error
/var/log/slurm/slurmctld.log           # Slurm controller
/var/log/slurm/slurmd.log              # Slurm daemon
```

### 설정 파일

```
/etc/nginx/sites-enabled/hpc-portal.conf    # Nginx config
/dashboard/backend_5010/.env                # Dashboard Backend env
/dashboard/kooCAEWebServer_5000/.env        # CAE Backend env (MOCK_MODE)
```

---

## 🧪 테스트 명령어

### curl로 API 테스트

```bash
# 세션 생성
curl -X POST http://localhost:5000/api/app/sessions \
  -H "Content-Type: application/json" \
  -d '{"app_id": "gedit", "user_id": "testuser"}'

# 세션 조회
curl http://localhost:5000/api/app/sessions

# 특정 세션 조회
SESSION_ID="app-session-..."
curl http://localhost:5000/api/app/sessions/$SESSION_ID

# 세션 삭제
curl -X DELETE http://localhost:5000/api/app/sessions/$SESSION_ID
```

### Frontend에서 API 호출 (DevTools Console)

```javascript
// 세션 생성
fetch('http://localhost:5000/api/app/sessions', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ app_id: 'gedit', user_id: 'testuser' })
})
  .then(r => r.json())
  .then(console.log)

// 세션 조회
fetch('http://localhost:5000/api/app/sessions')
  .then(r => r.json())
  .then(console.log)
```

---

## 📚 문서 링크

| 문서 | 경로 | 설명 |
|------|------|------|
| README | [app_5174/README.md](README.md) | 프로젝트 개요 |
| Phase 1 | [app_5174/PHASE1_COMPLETE.md](PHASE1_COMPLETE.md) | Foundation |
| Phase 2 | [app_5174/PHASE2_COMPLETE.md](PHASE2_COMPLETE.md) | BaseApp Framework |
| Phase 3 | [app_5174/docs/PHASE3_COMPLETE.md](docs/PHASE3_COMPLETE.md) | Apptainer & Deployment |
| Phase 4 | [app_5174/docs/PHASE4_SLURM_INTEGRATION_COMPLETE.md](docs/PHASE4_SLURM_INTEGRATION_COMPLETE.md) | Slurm Integration |
| SUMMARY | [app_5174/docs/SUMMARY.md](docs/SUMMARY.md) | 전체 요약 |
| ARCHITECTURE | [app_5174/docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 아키텍처 다이어그램 |
| STATUS | [app_5174/STATUS.md](STATUS.md) | 현재 상태 |

---

## 🔑 주요 명령어 치트시트

### 시스템 관리
```bash
./start_complete.sh         # 전체 시작
./stop_complete.sh          # 전체 종료
systemctl status nginx      # Nginx 상태
systemctl status slurmctld  # Slurm Controller 상태
```

### 개발
```bash
npm run dev                 # Frontend dev server
npm run build               # Frontend build
./venv/bin/python app.py    # Backend 직접 실행
```

### Slurm
```bash
squeue                      # Job 목록
sbatch <script>             # Job 제출
scancel <job_id>            # Job 취소
sinfo                       # 파티션 상태
```

### Apptainer
```bash
apptainer build <sif> <def> # 컨테이너 빌드
apptainer run <sif>         # 컨테이너 실행
./deploy_apptainers.sh      # 이미지 배포
```

### 디버깅
```bash
tail -f /tmp/*.log          # 로그 실시간 확인
lsof -i:<port>              # 포트 확인
ps aux | grep <process>     # 프로세스 확인
```

---

**Version**: 0.5.0 (Phase 5 완료)
**Last Updated**: 2025-10-24
