# Sunshine Apptainer 이미지 빌드 전략

**목적**: 기존 VNC 이미지를 기반으로 Sunshine 이미지 생성 (기존 시스템 무영향)

---

## 📋 네이밍 전략

### 원칙
1. **VNC 이미지**: `vnc_*.sif` 패턴 (VNC 서비스 전용)
2. **Sunshine 이미지**: `sunshine_*.sif` 패턴 (Moonlight 서비스 전용)
3. **필터링**: 파일명 prefix로 서비스 구분

### 이미지 매핑

| VNC 이미지 (기존) | Sunshine 이미지 (신규) | Desktop 환경 | CAE 앱 |
|-------------------|----------------------|--------------|--------|
| `vnc_desktop.sif` | `sunshine_desktop.sif` | XFCE4 | 없음 |
| `vnc_gnome.sif` | `sunshine_gnome.sif` | GNOME | 없음 |
| `vnc_gnome_lsprepost.sif` | `sunshine_gnome_lsprepost.sif` | GNOME | LS-PrePost |

---

## 🏗️ 빌드 방법

### Method 1: 기존 이미지 → Sandbox → Sunshine 추가 → 새 SIF (권장)

**장점**:
- ✅ 빠른 빌드 (기존 Desktop 환경 재사용)
- ✅ 기존 VNC 이미지 무수정
- ✅ 일관성 유지 (기존과 동일한 환경)

**단계**:

#### 1.1. sunshine_desktop.sif (vnc_desktop.sif 기반)

```bash
# viz-node001에서 실행

# Step 1: 기존 VNC 이미지 → Sandbox 복사
sudo apptainer build --sandbox /tmp/sunshine_desktop_sandbox /opt/apptainers/vnc_desktop.sif

# Step 2: Sunshine 설치
sudo apptainer exec --writable /tmp/sunshine_desktop_sandbox /bin/bash << 'EOF'
# Sunshine 다운로드 및 설치
wget -O /tmp/sunshine.deb https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-amd64.deb
apt-get update
apt-get install -y /tmp/sunshine.deb
rm /tmp/sunshine.deb

# Sunshine 설정 디렉토리 생성
mkdir -p /root/.config/sunshine

# 검증
sunshine --version
EOF

# Step 3: Sandbox → 새 SIF 파일 생성
sudo apptainer build /opt/apptainers/sunshine_desktop.sif /tmp/sunshine_desktop_sandbox

# Step 4: 권한 설정
sudo chmod 755 /opt/apptainers/sunshine_desktop.sif
sudo chown root:root /opt/apptainers/sunshine_desktop.sif

# Step 5: 정리
sudo rm -rf /tmp/sunshine_desktop_sandbox

# Step 6: 검증
apptainer exec --nv /opt/apptainers/sunshine_desktop.sif sunshine --version
```

#### 1.2. sunshine_gnome.sif (vnc_gnome.sif 기반)

```bash
# Step 1: Sandbox 생성
sudo apptainer build --sandbox /tmp/sunshine_gnome_sandbox /opt/apptainers/vnc_gnome.sif

# Step 2: Sunshine 설치
sudo apptainer exec --writable /tmp/sunshine_gnome_sandbox /bin/bash << 'EOF'
wget -O /tmp/sunshine.deb https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-amd64.deb
apt-get update
apt-get install -y /tmp/sunshine.deb
rm /tmp/sunshine.deb
mkdir -p /root/.config/sunshine
sunshine --version
EOF

# Step 3: SIF 생성
sudo apptainer build /opt/apptainers/sunshine_gnome.sif /tmp/sunshine_gnome_sandbox

# Step 4: 권한 설정
sudo chmod 755 /opt/apptainers/sunshine_gnome.sif
sudo chown root:root /opt/apptainers/sunshine_gnome.sif

# Step 5: 정리
sudo rm -rf /tmp/sunshine_gnome_sandbox

# Step 6: 검증
apptainer exec --nv /opt/apptainers/sunshine_gnome.sif sunshine --version
```

#### 1.3. sunshine_gnome_lsprepost.sif (vnc_gnome_lsprepost.sif 기반)

```bash
# Step 1: Sandbox 생성
sudo apptainer build --sandbox /tmp/sunshine_gnome_lsprepost_sandbox /opt/apptainers/vnc_gnome_lsprepost.sif

# Step 2: Sunshine 설치
sudo apptainer exec --writable /tmp/sunshine_gnome_lsprepost_sandbox /bin/bash << 'EOF'
wget -O /tmp/sunshine.deb https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-amd64.deb
apt-get update
apt-get install -y /tmp/sunshine.deb
rm /tmp/sunshine.deb
mkdir -p /root/.config/sunshine
sunshine --version
EOF

# Step 3: SIF 생성
sudo apptainer build /opt/apptainers/sunshine_gnome_lsprepost.sif /tmp/sunshine_gnome_lsprepost_sandbox

# Step 4: 권한 설정
sudo chmod 755 /opt/apptainers/sunshine_gnome_lsprepost.sif
sudo chown root:root /opt/apptainers/sunshine_gnome_lsprepost.sif

# Step 5: 정리
sudo rm -rf /tmp/sunshine_gnome_lsprepost_sandbox

# Step 6: 검증
apptainer exec --nv /opt/apptainers/sunshine_gnome_lsprepost.sif sunshine --version
apptainer exec --nv /opt/apptainers/sunshine_gnome_lsprepost.sif which lsprepost
```

---

## 🔍 빌드 검증

### 1. 파일 존재 확인

```bash
ls -lh /opt/apptainers/

# 예상 출력:
# -rwxr-xr-x 1 root root 511M Nov  3 23:27 vnc_desktop.sif
# -rwxr-xr-x 1 root root 841M Nov  3 23:27 vnc_gnome.sif
# -rwxr-xr-x 1 root root 1.3G Oct 23 21:44 vnc_gnome_lsprepost.sif
# -rwxr-xr-x 1 root root 550M Dec  6 XX:XX sunshine_desktop.sif          ← 신규
# -rwxr-xr-x 1 root root 880M Dec  6 XX:XX sunshine_gnome.sif            ← 신규
# -rwxr-xr-x 1 root root 1.4G Dec  6 XX:XX sunshine_gnome_lsprepost.sif  ← 신규
```

### 2. Sunshine 설치 확인

```bash
# sunshine_desktop.sif
apptainer exec /opt/apptainers/sunshine_desktop.sif sunshine --version
# 예상: Sunshine v0.23.1

# sunshine_gnome.sif
apptainer exec /opt/apptainers/sunshine_gnome.sif sunshine --version

# sunshine_gnome_lsprepost.sif
apptainer exec /opt/apptainers/sunshine_gnome_lsprepost.sif sunshine --version
apptainer exec /opt/apptainers/sunshine_gnome_lsprepost.sif which lsprepost
# 예상: /usr/local/bin/lsprepost (또는 설치 경로)
```

### 3. Desktop 환경 확인

```bash
# XFCE4 확인
apptainer exec /opt/apptainers/sunshine_desktop.sif which startxfce4
# 예상: /usr/bin/startxfce4

# GNOME 확인
apptainer exec /opt/apptainers/sunshine_gnome.sif which gnome-session
# 예상: /usr/bin/gnome-session
```

### 4. NVIDIA 확인

```bash
# GPU 접근 테스트
apptainer exec --nv /opt/apptainers/sunshine_desktop.sif nvidia-smi

# 예상 출력:
# +-----------------------------------------------------------------------------+
# | NVIDIA-SMI 535.xx.xx    Driver Version: 535.xx.xx    CUDA Version: 12.3    |
# |-------------------------------+----------------------+----------------------+
# | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
# ...
```

---

## 📊 이미지 크기 예상

| 이미지 | VNC 버전 | Sunshine 버전 | 증가분 |
|--------|----------|---------------|--------|
| Desktop (XFCE4) | 511 MB | ~550 MB | +40 MB |
| GNOME | 841 MB | ~880 MB | +40 MB |
| GNOME + LS-PrePost | 1.3 GB | ~1.4 GB | +40 MB |

**Sunshine 패키지 크기**: 약 30-40 MB

---

## 🔧 빌드 스크립트 (자동화)

### build_all_sunshine_images.sh

```bash
#!/bin/bash
set -e

echo "======================================================================"
echo "Sunshine Apptainer Images Builder"
echo "======================================================================"

# VNC 이미지 목록
VNC_IMAGES=(
    "vnc_desktop.sif:sunshine_desktop.sif:XFCE4"
    "vnc_gnome.sif:sunshine_gnome.sif:GNOME"
    "vnc_gnome_lsprepost.sif:sunshine_gnome_lsprepost.sif:GNOME+LS-PrePost"
)

BASE_DIR="/opt/apptainers"
SUNSHINE_URL="https://github.com/LizardByte/Sunshine/releases/download/v0.23.1/sunshine-ubuntu-22.04-amd64.deb"

for entry in "${VNC_IMAGES[@]}"; do
    IFS=':' read -r vnc_image sunshine_image desc <<< "$entry"

    echo ""
    echo "======================================================================"
    echo "Building: $sunshine_image ($desc)"
    echo "Source: $vnc_image"
    echo "======================================================================"

    # Check if source exists
    if [ ! -f "$BASE_DIR/$vnc_image" ]; then
        echo "❌ Source image not found: $BASE_DIR/$vnc_image"
        continue
    fi

    # Build sandbox
    sandbox_dir="/tmp/sunshine_sandbox_$$"
    echo "Step 1/5: Building sandbox from $vnc_image..."
    sudo apptainer build --sandbox "$sandbox_dir" "$BASE_DIR/$vnc_image"

    # Install Sunshine
    echo "Step 2/5: Installing Sunshine..."
    sudo apptainer exec --writable "$sandbox_dir" /bin/bash << EOF
        wget -q -O /tmp/sunshine.deb "$SUNSHINE_URL"
        apt-get update -qq
        apt-get install -y /tmp/sunshine.deb
        rm /tmp/sunshine.deb
        mkdir -p /root/.config/sunshine
        sunshine --version
EOF

    # Build SIF
    echo "Step 3/5: Building SIF image..."
    sudo apptainer build "$BASE_DIR/$sunshine_image" "$sandbox_dir"

    # Set permissions
    echo "Step 4/5: Setting permissions..."
    sudo chmod 755 "$BASE_DIR/$sunshine_image"
    sudo chown root:root "$BASE_DIR/$sunshine_image"

    # Cleanup
    echo "Step 5/5: Cleaning up..."
    sudo rm -rf "$sandbox_dir"

    # Verify
    echo "Verification:"
    ls -lh "$BASE_DIR/$sunshine_image"
    apptainer exec "$BASE_DIR/$sunshine_image" sunshine --version

    echo "✅ $sunshine_image built successfully!"
done

echo ""
echo "======================================================================"
echo "All Sunshine images built successfully!"
echo "======================================================================"
echo ""
echo "Images:"
ls -lh "$BASE_DIR"/sunshine_*.sif
```

---

## 🚀 빌드 실행

### 수동 빌드 (하나씩)

```bash
# viz-node001에 SSH 접속
ssh viz-node001

# 위의 1.1, 1.2, 1.3 명령어 순차 실행
```

### 자동 빌드 (전체)

```bash
# 빌드 스크립트 복사
scp /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/build_all_sunshine_images.sh \
    viz-node001:/tmp/

# viz-node001에서 실행
ssh viz-node001
chmod +x /tmp/build_all_sunshine_images.sh
sudo /tmp/build_all_sunshine_images.sh
```

**예상 소요 시간**: 15-30분 (네트워크 속도에 따라)

---

## ✅ 빌드 완료 후 확인

```bash
# 1. 파일 목록
ls -lh /opt/apptainers/

# 2. VNC 이미지 무결성 (날짜/크기 변경 없어야 함)
ls -lh /opt/apptainers/vnc_*.sif

# 3. Sunshine 이미지 존재
ls -lh /opt/apptainers/sunshine_*.sif

# 4. md5sum 확인 (VNC 이미지)
md5sum /opt/apptainers/vnc_desktop.sif
# 값이 이전과 동일해야 함!
```

---

## 📝 Backend API 업데이트

빌드 완료 후 `moonlight_api.py` 업데이트:

```python
# backend_moonlight_8004/moonlight_api.py

SUNSHINE_IMAGES = {
    "desktop": {  # vnc_desktop.sif 기반
        "name": "XFCE4 Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_desktop.sif",
        "description": "Lightweight XFCE4 desktop with Sunshine streaming",
        "icon": "🌞",
        "desktop_env": "xfce4",
        "default": True
    },
    "gnome": {  # vnc_gnome.sif 기반
        "name": "GNOME Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_gnome.sif",
        "description": "Full-featured GNOME desktop with Sunshine streaming",
        "icon": "🎨",
        "desktop_env": "gnome",
        "default": False
    },
    "gnome_lsprepost": {  # vnc_gnome_lsprepost.sif 기반
        "name": "GNOME + LS-PrePost (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_gnome_lsprepost.sif",
        "description": "GNOME desktop with LS-PrePost CAE software and Sunshine streaming",
        "icon": "🔧",
        "desktop_env": "gnome",
        "cae_app": "lsprepost",
        "default": False
    }
}
```

---

**다음 단계**: 빌드 스크립트 생성 및 viz-node에서 실행
