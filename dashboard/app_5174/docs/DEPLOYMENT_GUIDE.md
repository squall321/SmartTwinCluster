# Apptainer 이미지 배포 가이드

**작성일**: 2025-10-24
**대상**: App Framework 개발자

---

## 📁 배포 구조 개요

### 소스 위치 (access-node)

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/
│
├── apptainer/                                    # 기존 VNC 이미지 저장소
│   ├── viz-node-images/                         # VNC 이미지 소스
│   │   ├── vnc_desktop.sif (511MB)
│   │   ├── vnc_gnome.sif (841MB)
│   │   └── vnc_gnome_lsprepost.sif (1.3GB)
│   ├── compute-node-images/                     # Compute 이미지 소스
│   └── app/                                     # 앱별 정의 파일
│
└── dashboard/app_5174/                          # App Framework
    ├── apptainer/                               # 앱별 컨테이너 정의
    │   └── gedit.def                            # GEdit 정의 파일
    ├── gedit.sif                                # 빌드된 이미지 (로컬)
    └── deploy_gedit.sh                          # GEdit 배포 스크립트
```

### 배포 대상 위치 (viz-node001)

```
viz-node001 (192.168.122.252)
│
├── /opt/apptainers/                             # 기존 VNC 이미지
│   ├── vnc_desktop.sif
│   ├── vnc_gnome.sif
│   └── vnc_gnome_lsprepost.sif
│
└── /opt/apptainers/apps/                        # App Framework 전용
    └── gedit/
        └── gedit.sif (796MB)                    # GEdit 앱 이미지
```

---

## 🔧 새 앱 추가 방법 (단계별)

### 1단계: 컨테이너 정의 파일 작성

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174

# apptainer 디렉토리에 정의 파일 생성
nano apptainer/myapp.def
```

**정의 파일 템플릿**:

```apptainer
Bootstrap: docker
From: ubuntu:22.04

%post
    export DEBIAN_FRONTEND=noninteractive

    # 패키지 설치
    apt-get update && apt-get install -y \
        <your-app> \
        tigervnc-standalone-server \
        websockify \
        dbus-x11 \
        xfonts-base \
        x11-xserver-utils

    # VNC 설정
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

    # 앱 실행
    DISPLAY=:1 <your-app> &

    # websockify로 VNC WebSocket 제공
    websockify ${WEBSOCKIFY_PORT} localhost:${VNC_PORT}
```

### 2단계: 컨테이너 빌드

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174

# 빌드 (root 권한 필요)
sudo apptainer build myapp.sif apptainer/myapp.def

# 빌드 시간: 수 분 ~ 수십 분 (앱 크기에 따라)
# 결과: myapp.sif 파일 생성
```

**빌드 옵션**:
```bash
# 샌드박스 모드로 빌드 (디버깅용)
sudo apptainer build --sandbox myapp_sandbox/ apptainer/myapp.def

# 샌드박스에서 테스트
sudo apptainer shell --writable myapp_sandbox/
```

### 3단계: 로컬 테스트

```bash
# 로컬에서 컨테이너 실행 (테스트)
apptainer run \
    --env VNC_PORT=5901 \
    --env WEBSOCKIFY_PORT=6080 \
    myapp.sif

# 브라우저에서 ws://localhost:6080 접속하여 확인
```

### 4단계: viz-node001에 배포

#### Option A: GEdit 배포 스크립트 사용 (권장)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174

# GEdit 빌드 & 배포
./deploy_gedit.sh --build

# 이미 빌드된 이미지만 배포
./deploy_gedit.sh
```

#### Option B: 수동 배포

```bash
# 1. viz-node001에 디렉토리 생성
ssh viz-node001 "sudo mkdir -p /opt/apptainers/apps/myapp"

# 2. 이미지 전송
scp myapp.sif viz-node001:/tmp/

# 3. 이미지 이동 및 권한 설정
ssh viz-node001 "sudo mv /tmp/myapp.sif /opt/apptainers/apps/myapp/ && \
    sudo chown root:root /opt/apptainers/apps/myapp/myapp.sif && \
    sudo chmod 755 /opt/apptainers/apps/myapp/myapp.sif"
```

#### Option C: 전체 배포 스크립트 사용 (기존 시스템)

```bash
# 1. 이미지를 viz-node-images로 복사
cp myapp.sif /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/viz-node-images/

# 2. 전체 배포 실행
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./deploy_apptainers.sh --update

# 주의: 이 방법은 /opt/apptainers/ (루트)에 배포됨
# App Framework는 /opt/apptainers/apps/<app_name>/ 경로 사용
```

### 5단계: 배포 확인

```bash
# viz-node001에 배포된 이미지 확인
ssh viz-node001 "sudo ls -lh /opt/apptainers/apps/myapp/"

# 출력 예시:
# -rwxr-xr-x 1 root root 500M Oct 24 15:00 myapp.sif
```

---

## 🔄 기존 앱 업데이트 방법

### GEdit 업데이트 예시

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174

# 1. 정의 파일 수정
nano apptainer/gedit.def

# 2. 재빌드
sudo apptainer build gedit.sif apptainer/gedit.def

# 3. 재배포
./deploy_gedit.sh

# 4. 기존 세션 종료 및 재시작
# (실행 중인 Job이 있다면 scancel로 종료)
squeue  # 실행 중인 Job 확인
scancel <JOB_ID>  # Job 종료

# 5. 새 세션 생성으로 업데이트된 이미지 테스트
curl -X POST http://localhost:5000/api/app/sessions \
  -H "Content-Type: application/json" \
  -d '{"app_id": "gedit", "user_id": "testuser"}'
```

---

## 📋 Slurm Job 템플릿 추가

새 앱을 추가할 때는 Slurm Job 템플릿도 함께 생성해야 합니다.

### 1. Job 템플릿 생성

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/slurm_jobs

# 기존 템플릿 복사
cp gedit_vnc_job.sh myapp_vnc_job.sh

# 편집
nano myapp_vnc_job.sh
```

### 2. Job 템플릿 내용

```bash
#!/bin/bash
#SBATCH --job-name=myapp_vnc
#SBATCH --partition=viz
#SBATCH --nodes=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=2G                         # 앱 요구사항에 맞게 조정
#SBATCH --time=02:00:00
#SBATCH --output=/tmp/myapp_vnc_%j.out
#SBATCH --error=/tmp/myapp_vnc_%j.err

# 환경 변수 (Backend에서 전달)
SESSION_ID=${SESSION_ID:-"test-session"}
VNC_PORT=${VNC_PORT:-6080}
APPTAINER_IMAGE="/opt/apptainers/apps/myapp/myapp.sif"

# 실행 노드 정보 저장
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

### 3. Job 템플릿 테스트

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/slurm_jobs

# Job 제출
sbatch --export SESSION_ID=test-myapp,VNC_PORT=6080 myapp_vnc_job.sh

# Job 상태 확인
squeue

# Job 정보 확인
cat /tmp/app_session_test-myapp.info
```

---

## 🎯 Backend에 앱 등록

### 1. App Metadata 추가

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/kooCAEWebServer_5000

nano config/apps.json  # (또는 해당 설정 파일)
```

```json
{
  "apps": [
    {
      "id": "myapp",
      "name": "My App",
      "description": "My awesome application",
      "icon": "/static/icons/myapp.png",
      "resources": {
        "cpus": 2,
        "memory": "2Gi",
        "partition": "viz"
      },
      "display": {
        "type": "novnc",
        "resolution": "1280x720"
      },
      "job_template": "myapp_vnc_job.sh"
    }
  ]
}
```

### 2. SlurmAppManager에 Job 템플릿 매핑

```python
# services/slurm_app_manager.py

JOB_TEMPLATES = {
    'gedit': 'gedit_vnc_job.sh',
    'myapp': 'myapp_vnc_job.sh',  # 추가
}
```

---

## 🧪 테스트 체크리스트

새 앱을 배포한 후 다음 사항을 테스트하세요:

- [ ] **컨테이너 빌드 성공**
  ```bash
  sudo apptainer build myapp.sif apptainer/myapp.def
  ```

- [ ] **로컬 실행 테스트**
  ```bash
  apptainer run myapp.sif
  # ws://localhost:6080 접속 확인
  ```

- [ ] **viz-node001 배포 확인**
  ```bash
  ssh viz-node001 "sudo ls -lh /opt/apptainers/apps/myapp/"
  ```

- [ ] **Slurm Job 제출 테스트**
  ```bash
  sbatch --export SESSION_ID=test,VNC_PORT=6080 myapp_vnc_job.sh
  squeue  # Job 실행 확인
  ```

- [ ] **Job Info 파일 생성 확인**
  ```bash
  cat /tmp/app_session_test.info
  ```

- [ ] **noVNC 연결 테스트**
  - Job info에서 NODE_IP, VNC_PORT 확인
  - 브라우저에서 ws://<NODE_IP>:<VNC_PORT> 접속

- [ ] **Backend API 테스트**
  ```bash
  curl -X POST http://localhost:5000/api/app/sessions \
    -H "Content-Type: application/json" \
    -d '{"app_id": "myapp", "user_id": "testuser"}'
  ```

- [ ] **Frontend 통합 테스트** (Phase 6 이후)
  - Dashboard UI에서 앱 실행
  - 전체 플로우 검증

---

## 📚 참고 자료

### 파일 경로 요약

| 항목 | 경로 |
|------|------|
| GEdit 정의 파일 | `/dashboard/app_5174/apptainer/gedit.def` |
| GEdit 빌드 이미지 | `/dashboard/app_5174/gedit.sif` |
| GEdit 배포 스크립트 | `/dashboard/app_5174/deploy_gedit.sh` |
| GEdit Job 템플릿 | `/dashboard/app_5174/slurm_jobs/gedit_vnc_job.sh` |
| viz-node GEdit 이미지 | `viz-node001:/opt/apptainers/apps/gedit/gedit.sif` |
| 기존 VNC 이미지 소스 | `/apptainer/viz-node-images/*.sif` |
| 전체 배포 스크립트 | `/deploy_apptainers.sh` |

### 관련 문서

- [README.md](../README.md) - 프로젝트 개요
- [QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - 빠른 참조
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 시스템 아키텍처
- [Apptainer Documentation](https://apptainer.org/docs/)

---

## ❓ FAQ

### Q1: 빌드 시 "permission denied" 오류

**A**: `sudo`를 사용하여 빌드하세요:
```bash
sudo apptainer build myapp.sif apptainer/myapp.def
```

### Q2: viz-node001에 배포했는데 "Image not found" 오류

**A**: 경로를 확인하세요. App Framework는 `/opt/apptainers/apps/<app_name>/` 경로를 사용합니다:
```bash
# 올바른 경로
/opt/apptainers/apps/gedit/gedit.sif

# 잘못된 경로 (기존 VNC 이미지)
/opt/apptainers/gedit.sif
```

### Q3: Job 제출은 성공했는데 VNC 연결 실패

**A**: 다음을 확인하세요:
1. Job이 RUNNING 상태인지 확인: `squeue`
2. Job info 파일 존재 확인: `cat /tmp/app_session_*.info`
3. websockify 프로세스 확인: `ssh viz-node001 "ps aux | grep websockify"`
4. 포트가 열려있는지 확인: `ssh viz-node001 "lsof -i:<VNC_PORT>"`

### Q4: 이미지 크기가 너무 큼

**A**: 다음 방법으로 최적화하세요:
- 불필요한 패키지 제거
- Multi-stage build 사용
- `apt-get clean && rm -rf /var/lib/apt/lists/*` 추가

### Q5: 기존 VNC 이미지와 App Framework 이미지의 차이?

**A**:
- **기존 VNC 이미지** (`/opt/apptainers/*.sif`): 범용 VNC 데스크톱
- **App Framework 이미지** (`/opt/apptainers/apps/<app>/`): 특정 앱 전용, Job 템플릿 연동

---

**작성자**: KooSlurmInstallAutomation
**버전**: 0.5.0
**최종 업데이트**: 2025-10-24
