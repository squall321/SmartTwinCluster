# Moonlight/Sunshine 빌드 및 배포 가이드

**작성일**: 2025-12-06
**현재 상태**: Phase 1.1 완료 (Definition 파일 생성)

---

## 📋 Phase 1.1: Apptainer Definition 파일 생성 ✅

### 생성된 파일

1. ✅ `sunshine_xfce4.def` - Apptainer Definition 파일
2. ✅ `sunshine.conf.template` - Sunshine 설정 템플릿

### Definition 파일 특징

- **Base Image**: Ubuntu 22.04
- **NVIDIA Driver**: 535
- **CUDA**: 12.3
- **Desktop**: XFCE4
- **Sunshine**: v0.23.1
- **NVENC**: 하드웨어 인코딩 지원

---

## 📦 Phase 1.2: Apptainer 이미지 빌드

### ⚠️ 중요 사항

**이미지 빌드는 viz-node에서 수행해야 합니다!**
- 이유: NVIDIA GPU가 있는 노드에서 빌드해야 NVENC 관련 라이브러리가 제대로 설치됨
- Controller 노드에서 빌드하면 NVIDIA 드라이버 설치 실패 가능

### Step 1: viz-node로 파일 복사

```bash
# Controller에서 viz-node로 Definition 파일 복사
scp /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/sunshine_xfce4.def \
    viz-node001:/tmp/

# 설정 파일 템플릿도 복사
scp /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/sunshine.conf.template \
    viz-node001:/tmp/
```

### Step 2: viz-node에서 빌드

```bash
# viz-node001에 SSH 접속
ssh viz-node001

# 작업 디렉토리로 이동
cd /tmp

# Apptainer 이미지 빌드 (sudo 필요, 약 20-30분 소요)
sudo apptainer build sunshine_xfce4.sif sunshine_xfce4.def

# 빌드 로그 확인
# - NVIDIA 드라이버 설치 성공 여부
# - Sunshine 패키지 설치 성공 여부
# - 의존성 설치 성공 여부
```

**예상 빌드 시간**: 20-30분 (네트워크 속도에 따라 다름)

**예상 이미지 크기**: 2.5-3.5GB

### Step 3: 이미지 검증

```bash
# 이미지 정보 확인
apptainer inspect sunshine_xfce4.sif

# 이미지 실행 테스트 (--nv 옵션으로 GPU 접근)
apptainer exec --nv sunshine_xfce4.sif nvidia-smi

# 예상 출력: GPU 정보가 표시되어야 함
# GPU 0: NVIDIA RTX A6000 (또는 다른 모델)

# Sunshine 설치 확인
apptainer exec sunshine_xfce4.sif sunshine --version

# 예상 출력: Sunshine v0.23.1

# XFCE4 설치 확인
apptainer exec sunshine_xfce4.sif which startxfce4

# 예상 출력: /usr/bin/startxfce4
```

### Step 4: 이미지 배포

```bash
# viz-node001에서 이미지를 /opt/apptainers/로 복사 (sudo 필요)
sudo cp /tmp/sunshine_xfce4.sif /opt/apptainers/

# 권한 설정
sudo chown root:root /opt/apptainers/sunshine_xfce4.sif
sudo chmod 755 /opt/apptainers/sunshine_xfce4.sif

# 확인
ls -lh /opt/apptainers/sunshine_xfce4.sif

# 예상 출력:
# -rwxr-xr-x 1 root root 2.8G Dec  6 10:00 /opt/apptainers/sunshine_xfce4.sif
```

### Step 5: 기존 이미지 무결성 확인 ✅

```bash
# 기존 VNC 이미지가 수정되지 않았는지 확인
ls -lh /opt/apptainers/vnc_*.sif

# 예상 출력:
# vnc_desktop.sif
# vnc_gnome.sif
# vnc_gnome_lsprepost.sif
# sunshine_xfce4.sif  ← 새로 생성됨

# 날짜/크기가 변경되지 않았는지 확인!
```

---

## 🧪 Phase 1.3: 로컬 테스트 (viz-node)

### Sandbox 테스트

```bash
# viz-node001에서 실행

# 1. Sandbox 생성
mkdir -p /tmp/sunshine_test_sandbox
apptainer build --sandbox /tmp/sunshine_test_sandbox /opt/apptainers/sunshine_xfce4.sif

# 2. Instance 시작
apptainer instance start --nv --writable /tmp/sunshine_test_sandbox sunshine-test

# 3. Xvfb 시작 (X11 Display)
apptainer exec instance://sunshine-test Xvfb :99 -screen 0 1920x1080x24 &
sleep 2

# 4. XFCE4 시작
apptainer exec --cleanenv instance://sunshine-test bash -c "DISPLAY=:99 startxfce4 &"
sleep 5

# 5. Sunshine 시작 (테스트 포트 48000)
apptainer exec instance://sunshine-test bash -c \
    "DISPLAY=:99 CUDA_VISIBLE_DEVICES=0 sunshine --port 48000" &

# 6. 프로세스 확인
ps aux | grep sunshine
ps aux | grep Xvfb
ps aux | grep xfce

# 7. 포트 확인
lsof -i :48000

# 예상 출력: sunshine이 48000 포트를 리스닝하고 있어야 함

# 8. 정리
apptainer instance stop sunshine-test
rm -rf /tmp/sunshine_test_sandbox
```

### 예상 결과

✅ **성공 시**:
- Xvfb가 :99 디스플레이에서 실행 중
- XFCE4 프로세스가 실행 중
- Sunshine이 48000 포트에서 리스닝

❌ **실패 시**:
- Xvfb 실행 실패: X11 패키지 확인
- XFCE4 실행 실패: Desktop 환경 확인
- Sunshine 실행 실패: 의존성 확인 (libssl, libavcodec 등)
- 포트 리스닝 실패: 방화벽 또는 Sunshine 설정 확인

---

## 🔍 문제 해결

### 1. NVIDIA 드라이버 설치 실패

```bash
# Controller에서 빌드하면 실패할 수 있음
# 반드시 viz-node에서 빌드!

# viz-node에서 NVIDIA 드라이버 확인
nvidia-smi
```

### 2. Sunshine 다운로드 실패

```bash
# GitHub 릴리스 URL 확인
# https://github.com/LizardByte/Sunshine/releases

# 최신 버전으로 URL 업데이트
wget https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-amd64.deb
```

### 3. 의존성 패키지 버전 불일치

```bash
# Ubuntu 22.04 패키지 저장소 확인
apt-cache search libavcodec
apt-cache search libboost

# Definition 파일에서 패키지명 수정
```

### 4. 빌드 시간 초과

```bash
# 네트워크 속도가 느린 경우
# 로컬 미러 사용 또는 캐시 설정

# APT 캐시 설정
export APPTAINER_CACHEDIR=/tmp/apptainer-cache
```

---

## ✅ Phase 1.2 완료 체크리스트

- [ ] viz-node001에 SSH 접속
- [ ] Definition 파일 복사
- [ ] `sudo apptainer build sunshine_xfce4.sif sunshine_xfce4.def` 실행
- [ ] 빌드 성공 확인 (약 20-30분)
- [ ] `apptainer inspect sunshine_xfce4.sif` 실행
- [ ] `apptainer exec --nv sunshine_xfce4.sif nvidia-smi` 실행 (GPU 확인)
- [ ] `apptainer exec sunshine_xfce4.sif sunshine --version` 실행
- [ ] `/opt/apptainers/sunshine_xfce4.sif`로 복사
- [ ] 권한 설정 (755, root:root)
- [ ] 기존 VNC 이미지 무결성 확인
- [ ] Sandbox 테스트 (Xvfb + XFCE4 + Sunshine)
- [ ] 테스트 성공 확인

**완료 시**: Phase 2 (Slurm QoS 설정)로 진행

---

## 📊 다음 단계 미리보기

### Phase 2: Slurm QoS 설정

```bash
# moonlight QoS 생성
sudo sacctmgr add qos moonlight
sudo sacctmgr modify qos moonlight set \
    GraceTime=60 \
    MaxWall=8:00:00 \
    MaxTRESPerUser=gpu=2
```

### Phase 3: Backend 설치

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004

python3 -m venv venv
venv/bin/pip install -r requirements.txt
```

### Phase 4: Nginx 설정

```bash
sudo vi /etc/nginx/conf.d/auth-portal.conf
# /api/moonlight/ 경로 추가
```

### Phase 5: 테스트 및 검증

```bash
# Backend 실행
venv/bin/gunicorn -c gunicorn_config.py app:app

# API 테스트
curl -k https://110.15.177.120/api/moonlight/images
```

---

**현재 진행 상황**: Phase 1.1 완료, Phase 1.2 대기 중 (viz-node 접근 필요)
