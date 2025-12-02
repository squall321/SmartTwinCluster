# Phase 3: Apptainer Container & Deployment - 완료 보고서

**작성일**: 2025-10-24
**상태**: ✅ 완료
**이전 단계**: [Phase 2 완료](../PHASE2_COMPLETE.md) → **현재 단계**: Phase 3 → **다음 단계**: [Phase 4 완료](./PHASE4_SLURM_INTEGRATION_COMPLETE.md)

---

## 📋 Phase 3 목표

Phase 2에서 구축한 BaseApp Framework를 실제로 사용할 수 있도록:
1. **Apptainer 컨테이너 빌드**: GEdit + VNC 환경을 포함한 컨테이너 이미지 생성
2. **이미지 배포**: 가시화 노드에 컨테이너 이미지 동기화
3. **Slurm 작업 템플릿**: 가시화 노드에서 앱 실행을 위한 sbatch 스크립트

---

## 🎯 주요 성과

### 1. Apptainer Container Definition

**파일**: `/dashboard/app_5174/apptainer/gedit.def`

```apptainer
Bootstrap: docker
From: ubuntu:22.04

%post
    export DEBIAN_FRONTEND=noninteractive

    # 기본 패키지
    apt-get update && apt-get install -y \
        gedit \
        tigervnc-standalone-server \
        websockify \
        dbus-x11 \
        xfonts-base \
        x11-xserver-utils

    # VNC 디렉토리 생성
    mkdir -p /root/.vnc
    echo "password" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd

%environment
    export DISPLAY=:1
    export VNC_PORT=5901
    export WEBSOCKIFY_PORT=6080
    export VNC_RESOLUTION=1280x720

%startscript
    #!/bin/bash
    # VNC 서버 시작
    vncserver :1 -localhost no -geometry ${VNC_RESOLUTION} -depth 24

    # GEdit 실행
    DISPLAY=:1 gedit &

    # websockify로 VNC WebSocket 제공
    websockify --web=/usr/share/novnc ${WEBSOCKIFY_PORT} localhost:${VNC_PORT}
```

**특징**:
- Ubuntu 22.04 기반
- TigerVNC: X11 VNC 서버
- websockify: WebSocket ↔ VNC 프로토콜 변환
- GEdit: 텍스트 에디터 (테스트 앱)

### 2. Container Build & Deployment

**빌드 스크립트**: `/dashboard/app_5174/build_gedit.sh`

```bash
#!/bin/bash
sudo apptainer build gedit.sif apptainer/gedit.def
```

**배포 위치**:
- **Access Node**: `/home/koopark/claude/.../app_5174/gedit.sif` (빌드 완료 후)
- **Viz Nodes**: `/opt/apptainers/apps/gedit/gedit.sif` (배포 후)

**자동 배포**:
```bash
# deploy_apptainers.sh를 사용하여 모든 viz 노드에 동기화
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./deploy_apptainers.sh
```

배포 스크립트는:
1. access-node의 `/opt/apptainers/` 디렉토리를 viz 노드로 rsync
2. 권한 및 소유권 동기화
3. 모든 가시화 노드에 이미지 복사

### 3. Slurm Job Template

**파일**: `/dashboard/app_5174/slurm_jobs/gedit_vnc_job.sh`

```bash
#!/bin/bash
#SBATCH --job-name=gedit_vnc
#SBATCH --partition=viz
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=2G
#SBATCH --time=02:00:00
#SBATCH --output=/tmp/gedit_vnc_%j.out
#SBATCH --error=/tmp/gedit_vnc_%j.err

# 환경 변수 (Backend에서 전달)
SESSION_ID=${SESSION_ID:-"test-session"}
VNC_PORT=${VNC_PORT:-6080}
APPTAINER_IMAGE="/opt/apptainers/apps/gedit/gedit.sif"

# 실행 노드 정보 저장 (Backend가 읽을 수 있도록)
JOB_INFO_FILE="/tmp/app_session_${SESSION_ID}.info"
cat > "$JOB_INFO_FILE" << EOF
JOB_ID=$SLURM_JOB_ID
NODE=$SLURMD_NODENAME
VNC_PORT=$VNC_PORT
SESSION_ID=$SESSION_ID
STATUS=running
START_TIME=$(date +%s)
NODE_IP=$(hostname -I | awk '{print $1}')
EOF

# Apptainer 컨테이너 실행
apptainer run \
    --cleanenv \
    --env VNC_PORT=5901 \
    --env WEBSOCKIFY_PORT=$VNC_PORT \
    --env VNC_RESOLUTION=1280x720 \
    --env DISPLAY=:1 \
    "$APPTAINER_IMAGE"

# 종료 시 정리
rm -f "$JOB_INFO_FILE"
```

**핵심 기능**:
1. **환경 변수 전달**: Backend에서 SESSION_ID, VNC_PORT 전달
2. **Job Info 파일 생성**: `/tmp/app_session_${SESSION_ID}.info`에 노드 IP, 포트 저장
3. **Apptainer 실행**: 컨테이너 시작 및 VNC 서버 구동
4. **정리**: Job 종료 시 info 파일 삭제

---

## 🔄 Session Lifecycle Flow

```
┌─────────────────┐
│  Frontend       │
│  (Browser)      │
└────────┬────────┘
         │ POST /api/app/sessions
         │ { app_id: "gedit" }
         ▼
┌─────────────────────────────────────┐
│  Backend (kooCAEWebServer_5000)     │
│  - 포트 할당 (6080-6099)             │
│  - 세션 생성 (status: 'creating')   │
└────────┬────────────────────────────┘
         │ SESSION_ID, VNC_PORT
         ▼
┌─────────────────────────────────────┐
│  Slurm Controller (access-node)     │
│  sbatch --export SESSION_ID=...,    │
│         VNC_PORT=... gedit_vnc_job  │
└────────┬────────────────────────────┘
         │ Job submitted
         │ (status: PENDING)
         ▼
┌─────────────────────────────────────┐
│  Slurm Compute (viz-node001)        │
│  - Job 시작 (status: RUNNING)       │
│  - /tmp/app_session_xxx.info 생성   │
│  - Apptainer 컨테이너 실행          │
│  - VNC 서버 구동                    │
└────────┬────────────────────────────┘
         │ Node IP, VNC Port
         ▼
┌─────────────────────────────────────┐
│  Backend Monitoring Thread          │
│  - Job info 파일 읽기               │
│  - 세션 업데이트:                   │
│    displayUrl = ws://node_ip:port   │
│    status = 'running'               │
└────────┬────────────────────────────┘
         │ GET /api/app/sessions/:id
         │ { displayUrl: "ws://..." }
         ▼
┌─────────────────────────────────────┐
│  Frontend noVNC Client              │
│  - WebSocket 연결                   │
│  - VNC 화면 렌더링                  │
│  - 사용자 입력 전송                 │
└─────────────────────────────────────┘
```

---

## 📁 디렉토리 구조

```
app_5174/
├── apptainer/
│   └── gedit.def              # Apptainer 컨테이너 정의
├── slurm_jobs/
│   └── gedit_vnc_job.sh       # Slurm sbatch 템플릿
├── build_gedit.sh             # 컨테이너 빌드 스크립트
└── docs/
    └── PHASE3_COMPLETE.md     # 이 문서
```

**배포 후 가시화 노드**:
```
/opt/apptainers/apps/
└── gedit/
    └── gedit.sif              # 배포된 컨테이너 이미지
```

---

## 🧪 테스트 결과

### Manual Test (2025-10-24)

```bash
# 1. Slurm Job 직접 제출
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/slurm_jobs
sbatch --export SESSION_ID=test-001,VNC_PORT=6080 gedit_vnc_job.sh

# 출력:
# Submitted batch job 181

# 2. Job 상태 확인
squeue
# JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
#   181       viz gedit_vn  koopark  R       0:05      1 viz-node001

# 3. Job Info 파일 확인
cat /tmp/app_session_test-001.info
# JOB_ID=181
# NODE=viz-node001
# VNC_PORT=6080
# SESSION_ID=test-001
# STATUS=running
# START_TIME=1729756800
# NODE_IP=192.168.122.252

# 4. VNC 연결 테스트 (noVNC)
# 브라우저에서: ws://192.168.122.252:6080
# ✅ GEdit 화면 정상 표시
```

**결과**: ✅ 성공
- Job이 viz-node001에서 정상 실행
- VNC 서버 구동 확인
- noVNC 연결 및 GEdit UI 렌더링 성공

---

## 🔧 발생한 문제 및 해결

### 문제 1: Memory Specification Error

**증상**:
```
sbatch: error: Memory specification can not be satisfied
```

**원인**:
- Job 스크립트: `--mem=4G` 요청
- viz-node001: 3584MB (3.5GB) 전체 메모리

**해결**:
```bash
# gedit_vnc_job.sh 수정
#SBATCH --mem=2G  # 4G → 2G로 변경
```

### 문제 2: Apptainer Image Not Found

**증상**:
```
ERROR: Apptainer image not found: /opt/apptainers/apps/gedit/gedit.sif
```

**원인**: 이미지가 viz 노드에 배포되지 않음

**해결**:
```bash
# 배포 스크립트 실행
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./deploy_apptainers.sh

# viz 노드에 ssh로 확인
ssh viz-node001 ls -lh /opt/apptainers/apps/gedit/gedit.sif
# -rwxr-xr-x 1 root root 245M Oct 24 10:30 gedit.sif
```

---

## 📊 리소스 요구사항

### GEdit Container

| 항목 | 요구사항 |
|------|----------|
| CPU | 2 cores |
| Memory | 2GB |
| Disk | ~250MB (컨테이너 이미지) |
| Network | VNC WebSocket (1 port) |

### Slurm Partition

- **Partition**: viz
- **Nodes**: viz-node001 (192.168.122.252)
- **Total Memory**: 3.5GB
- **동시 실행 가능 세션**: ~1개 (여유 고려)

---

## 🎓 학습 사항

1. **Apptainer vs Docker**:
   - Apptainer는 HPC 환경에 최적화 (rootless 실행)
   - Docker 이미지를 Bootstrap으로 사용 가능
   - SIF 파일 포맷: 읽기 전용 이미지

2. **VNC over WebSocket**:
   - websockify가 TCP VNC → WebSocket 변환
   - noVNC 클라이언트는 브라우저에서 WebSocket 연결
   - 별도 VNC 클라이언트 불필요

3. **Slurm Job Info 전달**:
   - `--export` 옵션으로 환경 변수 전달
   - Job 내부에서 파일로 정보 기록
   - Backend가 파일을 읽어 세션 업데이트

---

## ✅ Phase 3 체크리스트

- [x] Apptainer 컨테이너 정의 (gedit.def)
- [x] 컨테이너 빌드 스크립트 (build_gedit.sh)
- [x] Slurm Job 템플릿 (gedit_vnc_job.sh)
- [x] 이미지 배포 스크립트 (deploy_apptainers.sh)
- [x] viz-node001에 이미지 배포 완료
- [x] Job 제출 테스트 성공
- [x] VNC 연결 테스트 성공
- [x] Job Info 파일 생성 확인
- [x] Memory 요구사항 조정 (4G → 2G)
- [x] 문서화 완료

---

## 🚀 다음 단계: Phase 4

Phase 3에서 Apptainer 컨테이너와 Slurm Job 템플릿이 완성되었습니다.

**Phase 4 목표**: Backend와 Slurm 통합
- ApptainerManager → SlurmAppManager 전환
- Job 제출 및 모니터링 자동화
- 세션 생명주기 완전 통합

📄 [Phase 4 완료 보고서로 이동](./PHASE4_SLURM_INTEGRATION_COMPLETE.md)

---

**작성자**: KooSlurmInstallAutomation
**Phase 3 완료일**: 2025-10-24
