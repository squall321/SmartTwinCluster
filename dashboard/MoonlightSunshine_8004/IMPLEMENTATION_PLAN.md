# Moonlight/Sunshine 초저지연 리눅스 화면 스트리밍 솔루션 (Port 8004)

## 📋 프로젝트 개요

**목표**: NVIDIA GameStream 프로토콜을 활용한 5-20ms 초저지연 리눅스 데스크톱 스트리밍 서비스 구축

**핵심 기술**:
- **Sunshine**: 오픈소스 GameStream 호스트 (서버 측, viz-node)
- **Moonlight**: GameStream 클라이언트 (웹 또는 네이티브)
- **NVENC/NVDEC**: NVIDIA 하드웨어 인코딩/디코딩
- **H.264/HEVC**: 고효율 비디오 코덱
- **UDP 기반 프로토콜**: 저지연 전송

**기대 성능**:
- 지연시간: 5-20ms (현재 50-210ms 대비 90% 개선)
- 해상도: 4K@60fps 지원
- 비트레이트: 10-50Mbps (동적 조정)
- 색심도: 10-bit HDR 지원 가능

---

## 🏗️ 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                         사용자 브라우저                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Moonlight Web Client (React + WebRTC)                    │  │
│  │  - H.264 Hardware Decode (MediaSource API)                │  │
│  │  - WebGL Canvas Rendering                                 │  │
│  │  - Input Forwarding (Keyboard/Mouse)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ WebRTC (UDP, DTLS)
                              │ H.264/HEVC Stream
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Nginx Reverse Proxy (443)                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  - WebRTC Signaling Proxy (WebSocket)                     │  │
│  │  - STUN/TURN Server (ICE Candidate Exchange)              │  │
│  │  - TLS Termination                                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ WebSocket (Signaling)
                              │ UDP (Media)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              WebRTC Gateway (Controller/Headnode)                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  - Session Manager (Python/Node.js)                       │  │
│  │  - WebRTC SFU (Selective Forwarding Unit)                 │  │
│  │  - ICE Server Integration                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ GameStream Protocol (UDP)
                              │ Video/Audio/Input Channels
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Sunshine Host (viz-node)                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Capture Layer:                                            │  │
│  │  ├─ X11 Screen Capture (via XComposite/Xdamage)           │  │
│  │  ├─ GPU Frame Grabber (DRM/KMS Direct Capture)            │  │
│  │  └─ Wayland Capture (PipeWire)                            │  │
│  │                                                             │  │
│  │  Encoding Layer (NVENC):                                   │  │
│  │  ├─ H.264 Hardware Encoding (5-10ms latency)              │  │
│  │  ├─ HEVC Support (더 나은 압축률)                          │  │
│  │  ├─ Adaptive Bitrate (Network Stats 기반)                 │  │
│  │  └─ Low-Latency Tuning (Preset: ultrafast/ll)             │  │
│  │                                                             │  │
│  │  Transport Layer:                                          │  │
│  │  ├─ UDP Multicast (GameStream Protocol)                   │  │
│  │  ├─ FEC (Forward Error Correction)                        │  │
│  │  └─ Congestion Control (BBR/CUBIC)                        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Desktop Environment (Apptainer Container)                 │  │
│  │  ├─ GNOME/XFCE4 + X11                                     │  │
│  │  ├─ GPU Passthrough (--nv)                                 │  │
│  │  ├─ CAE Applications (LS-PrePost, Abaqus, etc.)           │  │
│  │  └─ Virtual Audio Device (PulseAudio)                     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚠️ 기존 시스템 격리 전략 (CRITICAL)

### 원칙: 기존 VNC 서비스(8002)를 절대 건드리지 않음

**기존 시스템 (유지)**:
```
VNC Service 8002 (안정적 운영 중)
├── Apptainer Images: /opt/apptainers/vnc_*.sif
├── Sandboxes: /scratch/vnc_sandboxes/{username}_{image_id}/
├── Redis Keys: vnc:session:*
├── Slurm Partition: viz (QoS 없음)
├── Ports: 5900-5999 (VNC), 6900-6999 (noVNC)
├── API: /api/vnc/* (backend_5010/vnc_api.py)
└── Frontend: /vnc/ (정적 파일)
```

**신규 Moonlight/Sunshine (완전 독립)**:
```
Moonlight Service 8004 (신규 구축)
├── Apptainer Images: /opt/apptainers/sunshine_*.sif          ✅ 새 이미지
├── Sandboxes: /scratch/sunshine_sandboxes/{username}_{image_id}/  ✅ 새 디렉토리
├── Redis Keys: moonlight:session:*                           ✅ 새 키 패턴
├── Slurm Partition: viz --qos=moonlight                      ✅ QoS로 리소스 격리
├── Ports: 47989-48010 (Sunshine), 8004-8005 (Gateway)       ✅ 포트 분리
├── API: /api/moonlight/* (MoonlightSunshine_8004/backend/)  ✅ 새 API
└── Frontend: /moonlight/ (정적 파일)                         ✅ 새 경로
```

### 격리 체크리스트

#### 1. Apptainer 이미지 격리
- ❌ **하지 말 것**: 기존 `/opt/apptainers/vnc_desktop.sif` 수정
- ✅ **해야 할 것**: 새 이미지 생성
  ```bash
  # 기존 VNC 이미지 (건드리지 않음)
  /opt/apptainers/vnc_desktop.sif
  /opt/apptainers/vnc_gnome.sif
  /opt/apptainers/vnc_gnome_lsprepost.sif

  # 신규 Sunshine 이미지 (독립 생성)
  /opt/apptainers/sunshine_xfce4.sif
  /opt/apptainers/sunshine_gnome.sif
  /opt/apptainers/sunshine_gnome_lsprepost.sif
  ```

#### 2. Sandbox 디렉토리 격리
```bash
# 기존 VNC (유지)
/scratch/vnc_sandboxes/user01_xfce4/
/scratch/vnc_sandboxes/user01_gnome/

# 신규 Sunshine (새로 생성)
/scratch/sunshine_sandboxes/user01_xfce4/
/scratch/sunshine_sandboxes/user01_gnome/
```

#### 3. Redis 키 패턴 격리
```python
# 기존 VNC (vnc_api.py)
vnc:session:vnc-user01-1234567890

# 신규 Moonlight (완전히 다른 prefix)
moonlight:session:ml-user01-1234567890
```

#### 4. Slurm QoS 격리
```bash
# QoS 생성 (한 번만 실행)
sudo sacctmgr add qos moonlight
sudo sacctmgr modify qos moonlight set GraceTime=60 MaxWall=8:00:00

# Moonlight Job 제출 시
#SBATCH --partition=viz
#SBATCH --qos=moonlight  # 리소스 격리
```

#### 5. 포트 충돌 방지
```
기존 포트 (사용 중):
- 4430: Auth Backend
- 5000-5001: CAE Services
- 5010-5011: Dashboard Backend + WebSocket
- 5900-5999: VNC
- 6900-6999: noVNC
- 8080: SAML-IdP

신규 포트 (안전):
- 8004: Moonlight HTTP API       ✅ 충돌 없음
- 8005: Moonlight WebSocket      ✅ 충돌 없음
- 47989-48010: Sunshine Protocol ✅ 충돌 없음
```

#### 6. Nginx 설정 격리
```nginx
# ❌ 잘못된 방법: 별도 파일에서 443 포트 재사용
# /etc/nginx/conf.d/moonlight.conf
server {
    listen 443 ssl http2;  # ❌ auth-portal.conf와 충돌!
}

# ✅ 올바른 방법: 기존 파일에 location 추가
# /etc/nginx/conf.d/auth-portal.conf 내부에 추가
server {
    listen 443 ssl http2;
    server_name _;

    # 기존 VNC 설정 (유지)
    location /vnc { ... }
    location ~ ^/vncproxy/([0-9]+)/(.*)$ { ... }

    # 신규 Moonlight 추가 (location만)
    location /moonlight/ { ... }                 ✅
    location /api/moonlight/ { ... }             ✅
    location /moonlight/signaling { ... }        ✅
}
```

#### 7. API 라우팅 격리
```python
# backend_5010/app.py (기존 VNC API는 유지)
from vnc_api import vnc_bp  # 기존 (건드리지 않음)
app.register_blueprint(vnc_bp)  # /api/vnc/*

# MoonlightSunshine_8004/backend/app.py (완전히 별도 프로세스)
from moonlight_api import moonlight_bp  # 신규
app.register_blueprint(moonlight_bp)  # /api/moonlight/*
```

#### 8. 프로세스 격리
```bash
# 기존 VNC API (backend_5010, Gunicorn, Port 5010)
gunicorn -c gunicorn_config.py app:app  # vnc_api.py 포함

# 신규 Moonlight Backend (완전 독립 디렉토리, Gunicorn, Port 8004)
# backend_moonlight_8004/ ← backend_5010/과 완전 분리
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004
venv/bin/gunicorn -c gunicorn_config.py app:app  # moonlight_api.py 포함
```

---

## 📦 Phase 1: 기본 인프라 구축 (1-2주)

### 1.1. Sunshine 서버 설치 및 설정 (viz-node)

**목표**: viz-node에서 **독립적인** Sunshine 전용 Apptainer 이미지 생성

⚠️ **중요**: 기존 VNC 이미지(`/opt/apptainers/vnc_*.sif`)를 절대 수정하지 않음!

#### 설치 방법 (완전 독립)

**Step 1: 새 Apptainer Definition 파일 생성**
```bash
# 작업 디렉토리
mkdir -p /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/sunshine
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/sunshine

# Sunshine 전용 Definition 파일 생성
cat > sunshine_xfce4.def << 'EOF'
Bootstrap: docker
From: ubuntu:22.04

%post
    # 기본 패키지
    apt-get update
    apt-get install -y wget curl gnupg software-properties-common

    # NVIDIA Driver + CUDA (NVENC 지원)
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
    dpkg -i cuda-keyring_1.0-1_all.deb
    apt-get update
    apt-get install -y cuda-toolkit-12-3 nvidia-driver-535

    # Sunshine 설치 (최신 버전)
    wget -qO- https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-ubuntu-22.04-amd64.deb
    apt-get install -y ./sunshine-ubuntu-22.04-amd64.deb

    # Desktop Environment (XFCE4)
    apt-get install -y xfce4 xfce4-goodies dbus-x11

    # 필수 유틸리티
    apt-get install -y pulseaudio x11vnc xvfb

    # 정리
    apt-get clean
    rm -rf /var/lib/apt/lists/*

%environment
    export DISPLAY=:1
    export CUDA_VISIBLE_DEVICES=0
    export NVIDIA_VISIBLE_DEVICES=0
    export NVIDIA_DRIVER_CAPABILITIES=all

%runscript
    # Sunshine 시작
    sunshine --config ~/.config/sunshine/sunshine.conf
EOF
```

**Step 2: Apptainer 이미지 빌드 (viz-node에서)**
```bash
# viz-node에 SSH 접속
ssh viz-node001

# 이미지 빌드 (sudo 필요)
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/sunshine
sudo apptainer build /opt/apptainers/sunshine_xfce4.sif sunshine_xfce4.def

# 생성 확인
ls -lh /opt/apptainers/sunshine_xfce4.sif
# Expected: 2-3GB
```

**Step 3: 기존 시스템과 격리 확인**
```bash
# 기존 VNC 이미지 (건드리지 않음)
ls -lh /opt/apptainers/vnc_*.sif
# vnc_desktop.sif
# vnc_gnome.sif
# vnc_gnome_lsprepost.sif

# 신규 Sunshine 이미지 (독립)
ls -lh /opt/apptainers/sunshine_*.sif
# sunshine_xfce4.sif      ✅ 신규
# sunshine_gnome.sif      ✅ 추후 생성
```

⚠️ **중요**: 기존 VNC 이미지를 **절대 수정하거나 복사하지 않음**
- 오직 **Definition 파일로부터 처음부터 새로 빌드**
- 이렇게 하면 완전한 격리가 보장됨

#### Sunshine 설정 파일 (`~/.config/sunshine/sunshine.conf`)
```ini
# 네트워크 설정
address_family = both
port = 47989
upnp = disabled
ping_timeout = 10000

# 스트리밍 품질 설정
channels = 2
fps = [10, 30, 60, 120]  # 지원 프레임레이트
resolutions = [
    "1920x1080",
    "2560x1440",
    "3840x2160"
]

# 비디오 인코딩 (NVENC)
encoder = nvenc
sw_preset = ultrafast
nv_preset = p1              # P1 (fastest) ~ P7 (slowest)
nv_rc = cbr                 # CBR (Constant Bitrate)
nv_coder = cabac           # CABAC entropy coding
nv_h264_profile = high
bitrate = 20000            # 20Mbps (동적 조정)
slices_per_frame = 1
min_threads = 2

# 오디오
audio_sink = pulse         # PulseAudio

# 캡처 방식
capture = x11              # x11 | wayland | kms

# 입력 장치
gamepad = disabled
keyboard = enabled
mouse = enabled
controller = enabled

# 보안
credentials_file = /home/sunshine/.config/sunshine/credentials.json
```

#### Sunshine 실행 스크립트 (`start_sunshine.sh`)
```bash
#!/bin/bash
# Sunshine 호스트 시작 스크립트

DISPLAY=:1  # VNC Display 번호와 일치
SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"
SUNSHINE_LOG="$HOME/.config/sunshine/sunshine.log"

# NVENC 환경변수
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=0
export NVIDIA_DRIVER_CAPABILITIES=all

# X11 권한 설정
xhost +local:

# Sunshine 실행 (백그라운드)
sunshine \
    --config "$SUNSHINE_CONFIG_DIR/sunshine.conf" \
    --log "$SUNSHINE_LOG" \
    --min-log-level info &

SUNSHINE_PID=$!
echo $SUNSHINE_PID > "$SUNSHINE_CONFIG_DIR/sunshine.pid"
echo "✅ Sunshine started (PID: $SUNSHINE_PID, Display: $DISPLAY)"
```

---

### 1.2. NVENC 최적화 설정

#### NVIDIA Driver 확인
```bash
# Driver 버전 (최소 520.xx 이상 권장)
nvidia-smi

# NVENC 지원 확인
nvidia-smi -q | grep "Encoder"
# Expected: Encoder: 3 (동시 3개 세션 인코딩 가능)
```

#### NVENC 파라미터 최적화
```c
// Sunshine NVENC 설정 (소스 수정 시)
NV_ENC_CONFIG config = {
    .rcParams = {
        .rateControlMode = NV_ENC_PARAMS_RC_CBR,      // Constant Bitrate
        .averageBitRate = 20000000,                    // 20Mbps
        .maxBitRate = 30000000,                        // 30Mbps peak
        .vbvBufferSize = 20000000,                     // 1초 버퍼
        .vbvInitialDelay = 10000000,                   // 0.5초 초기 지연
    },
    .gopLength = 60,                                   // 1초 GOP (60fps 기준)
    .frameIntervalP = 1,                               // 모든 프레임 P-frame (낮은 지연)
    .encodeCodecConfig.h264Config = {
        .idrPeriod = 60,                               // 1초마다 IDR
        .sliceMode = 1,                                // 슬라이스 모드
        .sliceModeData = 1,                            // 슬라이스 1개
        .repeatSPSPPS = 1,                             // SPS/PPS 반복 전송
        .enableIntraRefresh = 1,                       // Intra Refresh (더 부드러운 화면)
        .maxNumRefFrames = 1,                          // 참조 프레임 최소화 (지연 감소)
        .adaptiveTransformMode = NV_ENC_H264_ADAPTIVE_TRANSFORM_DISABLE,
        .fmoMode = NV_ENC_H264_FMO_DISABLE,
    },
    .presetGUID = NV_ENC_PRESET_LOW_LATENCY_HQ_GUID,  // 저지연 프리셋
};
```

**최적화 목표**:
- **GOP Length**: 짧게 (60 = 1초) → IDR 프레임 자주 전송 → 에러 복구 빠름
- **B-Frames**: 0개 → 참조 프레임 대기 시간 제거
- **Slices**: 1개 → 인코딩 오버헤드 최소화
- **Rate Control**: CBR → 일정한 대역폭 유지

---

### 1.3. 네트워크 최적화 (Controller ↔ viz-node)

#### UDP 버퍼 크기 증가
```bash
# Controller와 viz-node 양쪽 모두 설정
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
sudo sysctl -w net.core.wmem_default=26214400

# UDP 버퍼 (25MB)
sudo sysctl -w net.ipv4.udp_rmem_min=8192
sudo sysctl -w net.ipv4.udp_wmem_min=8192

# /etc/sysctl.conf에 영구 저장
cat <<EOF | sudo tee -a /etc/sysctl.conf
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
EOF
```

#### BBR Congestion Control 활성화
```bash
# BBR은 구글이 개발한 TCP/UDP 혼잡 제어 알고리즘
# 낮은 지연시간과 높은 처리량 최적화

sudo modprobe tcp_bbr
echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf

sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.core.default_qdisc=fq

# /etc/sysctl.conf
cat <<EOF | sudo tee -a /etc/sysctl.conf
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
EOF
```

---

## 📦 Phase 2: WebRTC Gateway 구축 (2-3주)

### 2.1. WebRTC Signaling Server (Node.js)

**목표**: 브라우저 ↔ Sunshine 간 WebRTC 연결 협상

#### 기술 스택
- **Node.js + Express**: HTTP/WebSocket 서버
- **ws**: WebSocket 라이브러리
- **wrtc** (또는 **mediasoup**): WebRTC SFU

#### 디렉토리 구조
```
MoonlightSunshine_8004/
├── backend/
│   ├── server.js                 # WebRTC Signaling Server
│   ├── sunshine_bridge.js        # Sunshine GameStream 프로토콜 브릿지
│   ├── session_manager.js        # 세션 관리 (Redis)
│   ├── stun_turn_server.js       # STUN/TURN 서버 (coturn)
│   └── package.json
├── frontend/
│   ├── src/
│   │   ├── MoonlightClient.tsx   # Moonlight Web Client (React)
│   │   ├── WebRTCHandler.ts      # WebRTC 연결 관리
│   │   ├── VideoRenderer.tsx     # Hardware Decode + Canvas
│   │   └── InputForwarder.ts     # 키보드/마우스 입력
│   ├── public/
│   └── package.json
├── nginx/
│   └── moonlight.conf            # Nginx 설정
└── IMPLEMENTATION_PLAN.md        # 이 문서
```

#### Signaling Server (`backend/server.js`)
```javascript
const express = require('express');
const WebSocket = require('ws');
const { RTCPeerConnection, RTCSessionDescription } = require('wrtc');
const SunshineBridge = require('./sunshine_bridge');
const SessionManager = require('./session_manager');

const app = express();
const PORT = 8004;

// WebSocket 서버 (Signaling)
const wss = new WebSocket.Server({ port: 8005 });

// STUN/TURN 서버 설정
const ICE_SERVERS = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:110.15.177.120:3478' },  // 자체 STUN
    {
        urls: 'turn:110.15.177.120:3478',
        username: 'moonlight',
        credential: 'sunshine2025'
    }
];

// WebRTC Peer Connection 관리
const peers = new Map();

wss.on('connection', async (ws, req) => {
    const sessionId = req.url.split('?session=')[1];
    console.log(`[Signaling] New connection: ${sessionId}`);

    // Sunshine 세션 정보 조회 (Redis)
    const session = await SessionManager.getSession(sessionId);
    if (!session) {
        ws.send(JSON.stringify({ error: 'Invalid session' }));
        ws.close();
        return;
    }

    // Sunshine 호스트 연결
    const sunshineHost = session.node;  // viz-node IP
    const sunshinePort = session.sunshine_port;  // 47989

    // WebRTC Peer Connection 생성
    const pc = new RTCPeerConnection({
        iceServers: ICE_SERVERS,
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require'
    });

    peers.set(sessionId, { ws, pc, sunshineHost, sunshinePort });

    // ICE Candidate 이벤트
    pc.onicecandidate = (event) => {
        if (event.candidate) {
            ws.send(JSON.stringify({
                type: 'ice_candidate',
                candidate: event.candidate
            }));
        }
    };

    // Track 수신 (Sunshine → WebRTC)
    pc.ontrack = (event) => {
        console.log(`[WebRTC] Received track: ${event.track.kind}`);
    };

    // Signaling 메시지 처리
    ws.on('message', async (message) => {
        const data = JSON.parse(message);

        switch (data.type) {
            case 'offer':
                // SDP Offer 수신 → Sunshine에 전달
                await handleOffer(sessionId, data.sdp);
                break;

            case 'ice_candidate':
                // ICE Candidate 수신
                await pc.addIceCandidate(data.candidate);
                break;

            case 'start_stream':
                // Sunshine 스트림 시작 요청
                await SunshineBridge.startStream(sunshineHost, sunshinePort, sessionId);
                break;
        }
    });

    ws.on('close', () => {
        console.log(`[Signaling] Connection closed: ${sessionId}`);
        pc.close();
        peers.delete(sessionId);
    });
});

// SDP Offer 처리
async function handleOffer(sessionId, offer) {
    const peer = peers.get(sessionId);
    if (!peer) return;

    const { pc, sunshineHost, sunshinePort } = peer;

    // Remote Description 설정
    await pc.setRemoteDescription(new RTCSessionDescription({
        type: 'offer',
        sdp: offer
    }));

    // Sunshine에 연결하여 비디오 스트림 요청
    const sunshineStream = await SunshineBridge.getStream(
        sunshineHost,
        sunshinePort,
        { codec: 'h264', bitrate: 20000000, fps: 60, resolution: '1920x1080' }
    );

    // 비디오 트랙 추가
    sunshineStream.getTracks().forEach(track => {
        pc.addTrack(track, sunshineStream);
    });

    // SDP Answer 생성
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    // Answer를 클라이언트에 전송
    peer.ws.send(JSON.stringify({
        type: 'answer',
        sdp: answer.sdp
    }));
}

// HTTP API
app.get('/api/sessions/:sessionId', async (req, res) => {
    const session = await SessionManager.getSession(req.params.sessionId);
    res.json(session);
});

app.listen(PORT, () => {
    console.log(`✅ Moonlight/Sunshine WebRTC Gateway running on port ${PORT}`);
});
```

---

### 2.2. Sunshine GameStream 프로토콜 브릿지

#### GameStream 프로토콜 개요
- **포트**: 47989 (TCP, Handshake) + 47998-48010 (UDP, Media)
- **Handshake**: HTTPS 기반 인증 및 세션 협상
- **Video Stream**: UDP Multicast (RTP/RTCP)
- **Audio Stream**: UDP (별도 채널)
- **Input**: UDP (키보드/마우스 이벤트)

#### Sunshine Bridge (`backend/sunshine_bridge.js`)
```javascript
const https = require('https');
const dgram = require('dgram');
const crypto = require('crypto');

class SunshineBridge {
    constructor(host, port = 47989) {
        this.host = host;
        this.port = port;
        this.sessionId = null;
        this.udpSockets = [];
    }

    // Sunshine에 인증 및 세션 시작
    async startStream(options) {
        const { codec, bitrate, fps, resolution } = options;

        // Step 1: Pairing (최초 1회만)
        const pairingPin = await this.pair();

        // Step 2: Launch App (Desktop Session)
        const appId = 'Desktop';  // Sunshine에서 정의된 앱 ID
        const launchResponse = await this.launchApp(appId, {
            width: parseInt(resolution.split('x')[0]),
            height: parseInt(resolution.split('x')[1]),
            fps: fps,
            bitrate: bitrate,
            codec: codec
        });

        this.sessionId = launchResponse.sessionId;

        // Step 3: UDP 포트 바인딩 (Video/Audio/Input)
        await this.bindUdpPorts();

        return {
            sessionId: this.sessionId,
            videoPort: 47998,
            audioPort: 47999,
            inputPort: 48000
        };
    }

    // Pairing 요청
    async pair() {
        const pin = crypto.randomInt(0, 9999).toString().padStart(4, '0');
        const salt = crypto.randomBytes(16).toString('hex');

        const response = await this.httpsRequest('/pair', {
            method: 'GET',
            params: {
                uniqueid: this.getUniqueId(),
                devicename: 'MoonlightWebClient',
                updateState: 1,
                phrase: 'getservercert',
                salt: salt,
                clientcert: this.getClientCert()
            }
        });

        console.log(`✅ Paired with Sunshine (PIN: ${pin})`);
        return pin;
    }

    // 앱 실행 (Desktop)
    async launchApp(appId, options) {
        const response = await this.httpsRequest('/launch', {
            method: 'GET',
            params: {
                appid: appId,
                mode: `${options.width}x${options.height}x${options.fps}`,
                additionalStates: 1,
                sops: 1,
                rikey: crypto.randomBytes(16).toString('hex'),
                rikeyid: 1,
                localAudioPlayMode: 1,
                surroundAudioInfo: '196610',
                remoteControllersBitmap: 0,
                gcmap: 1
            }
        });

        return {
            sessionId: response.sessionUrl.split('sessionId=')[1]
        };
    }

    // UDP 포트 바인딩
    async bindUdpPorts() {
        // Video port (47998)
        this.videoSocket = dgram.createSocket('udp4');
        this.videoSocket.bind(47998);

        // Audio port (47999)
        this.audioSocket = dgram.createSocket('udp4');
        this.audioSocket.bind(47999);

        // Input port (48000)
        this.inputSocket = dgram.createSocket('udp4');
        this.inputSocket.bind(48000);

        console.log('✅ UDP ports bound: 47998 (video), 47999 (audio), 48000 (input)');
    }

    // HTTPS 요청 (Sunshine API)
    async httpsRequest(path, options) {
        return new Promise((resolve, reject) => {
            const req = https.request({
                hostname: this.host,
                port: this.port,
                path: path + '?' + new URLSearchParams(options.params).toString(),
                method: options.method || 'GET',
                rejectUnauthorized: false  // Self-signed cert
            }, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => resolve(JSON.parse(data)));
            });

            req.on('error', reject);
            req.end();
        });
    }

    // 고유 ID 생성
    getUniqueId() {
        return crypto.randomBytes(8).toString('hex');
    }

    // 클라이언트 인증서 (간소화)
    getClientCert() {
        return crypto.randomBytes(256).toString('base64');
    }

    // 비디오 스트림 수신 → WebRTC로 전달
    getVideoStream() {
        const { Readable } = require('stream');
        const stream = new Readable({ read() {} });

        this.videoSocket.on('message', (msg) => {
            stream.push(msg);  // RTP 패킷을 WebRTC로 전달
        });

        return stream;
    }
}

module.exports = SunshineBridge;
```

---

## 📦 Phase 3: 웹 클라이언트 구현 (2-3주)

### 3.1. Moonlight Web Client (React + TypeScript)

#### 핵심 기능
1. **WebRTC 연결**: Signaling Server와 통신
2. **Hardware Video Decode**: MediaSource Extensions API
3. **Canvas Rendering**: WebGL 가속 렌더링
4. **Input Forwarding**: 키보드/마우스 이벤트 → UDP

#### WebRTC Handler (`frontend/src/WebRTCHandler.ts`)
```typescript
import { io, Socket } from 'socket.io-client';

interface StreamConfig {
    sessionId: string;
    resolution: string;
    fps: number;
    bitrate: number;
}

export class WebRTCHandler {
    private pc: RTCPeerConnection | null = null;
    private ws: Socket | null = null;
    private videoElement: HTMLVideoElement;
    private dataChannel: RTCDataChannel | null = null;

    constructor(videoElement: HTMLVideoElement) {
        this.videoElement = videoElement;
    }

    async connect(config: StreamConfig) {
        // WebSocket 연결 (Signaling)
        this.ws = io(`wss://110.15.177.120:8005?session=${config.sessionId}`);

        // WebRTC Peer Connection 생성
        this.pc = new RTCPeerConnection({
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
                { urls: 'turn:110.15.177.120:3478', username: 'moonlight', credential: 'sunshine2025' }
            ],
            bundlePolicy: 'max-bundle',
            rtcpMuxPolicy: 'require'
        });

        // ICE Candidate 이벤트
        this.pc.onicecandidate = (event) => {
            if (event.candidate) {
                this.ws?.emit('ice_candidate', { candidate: event.candidate });
            }
        };

        // Track 수신 (비디오 스트림)
        this.pc.ontrack = (event) => {
            console.log('[WebRTC] Received video track');
            this.videoElement.srcObject = event.streams[0];
        };

        // Data Channel (입력 이벤트)
        this.dataChannel = this.pc.createDataChannel('input', { ordered: true });
        this.dataChannel.onopen = () => {
            console.log('[WebRTC] Data channel opened');
        };

        // Offer 생성
        const offer = await this.pc.createOffer({
            offerToReceiveVideo: true,
            offerToReceiveAudio: true
        });
        await this.pc.setLocalDescription(offer);

        // Offer 전송
        this.ws.emit('offer', { sdp: offer.sdp });

        // Answer 수신
        this.ws.on('answer', async (data: { sdp: string }) => {
            await this.pc!.setRemoteDescription(new RTCSessionDescription({
                type: 'answer',
                sdp: data.sdp
            }));
        });

        // ICE Candidate 수신
        this.ws.on('ice_candidate', async (data: { candidate: RTCIceCandidateInit }) => {
            await this.pc!.addIceCandidate(new RTCIceCandidate(data.candidate));
        });
    }

    // 키보드 입력 전송
    sendKeyEvent(keyCode: number, pressed: boolean) {
        if (this.dataChannel?.readyState === 'open') {
            const packet = new Uint8Array([
                0x03,  // Keyboard packet type
                pressed ? 0x01 : 0x00,
                keyCode & 0xFF,
                (keyCode >> 8) & 0xFF
            ]);
            this.dataChannel.send(packet);
        }
    }

    // 마우스 입력 전송
    sendMouseEvent(x: number, y: number, button: number) {
        if (this.dataChannel?.readyState === 'open') {
            const packet = new Uint8Array([
                0x04,  // Mouse packet type
                button,
                x & 0xFF, (x >> 8) & 0xFF,
                y & 0xFF, (y >> 8) & 0xFF
            ]);
            this.dataChannel.send(packet);
        }
    }

    disconnect() {
        this.dataChannel?.close();
        this.pc?.close();
        this.ws?.disconnect();
    }
}
```

#### Video Renderer with Hardware Decode (`frontend/src/VideoRenderer.tsx`)
```tsx
import React, { useEffect, useRef } from 'react';
import { WebRTCHandler } from './WebRTCHandler';
import { InputForwarder } from './InputForwarder';

interface VideoRendererProps {
    sessionId: string;
    resolution: string;
    fps: number;
}

export const VideoRenderer: React.FC<VideoRendererProps> = ({ sessionId, resolution, fps }) => {
    const videoRef = useRef<HTMLVideoElement>(null);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const webrtcRef = useRef<WebRTCHandler | null>(null);

    useEffect(() => {
        if (!videoRef.current) return;

        // WebRTC Handler 초기화
        webrtcRef.current = new WebRTCHandler(videoRef.current);
        webrtcRef.current.connect({
            sessionId,
            resolution,
            fps,
            bitrate: 20000000  // 20Mbps
        });

        // Video Element 설정
        const video = videoRef.current;
        video.addEventListener('loadedmetadata', () => {
            console.log(`✅ Video loaded: ${video.videoWidth}x${video.videoHeight}`);
            video.play();
        });

        // Input Forwarder 설정
        const inputForwarder = new InputForwarder(canvasRef.current!, webrtcRef.current);
        inputForwarder.attach();

        return () => {
            webrtcRef.current?.disconnect();
            inputForwarder.detach();
        };
    }, [sessionId, resolution, fps]);

    return (
        <div style={{ position: 'relative', width: '100%', height: '100%', backgroundColor: '#000' }}>
            {/* Hardware Decoded Video (hidden) */}
            <video
                ref={videoRef}
                style={{ display: 'none' }}
                autoPlay
                playsInline
                muted
            />

            {/* Canvas for rendering (optional, for custom processing) */}
            <canvas
                ref={canvasRef}
                style={{
                    width: '100%',
                    height: '100%',
                    objectFit: 'contain',
                    cursor: 'none'
                }}
            />

            {/* Stats Overlay */}
            <div style={{
                position: 'absolute',
                top: 10,
                left: 10,
                color: '#0f0',
                fontFamily: 'monospace',
                fontSize: 12,
                backgroundColor: 'rgba(0,0,0,0.5)',
                padding: 5
            }}>
                <div>Session: {sessionId}</div>
                <div>Resolution: {resolution}</div>
                <div>FPS: {fps}</div>
                <div>Latency: <span id="latency">-- ms</span></div>
            </div>
        </div>
    );
};
```

---

## 📦 Phase 4: 성능 측정 및 최적화 (1-2주)

### 4.1. 지연시간 측정

#### End-to-End Latency 측정 방법
```javascript
// 클라이언트 측: 타임스탬프 전송
const sendTimestamp = () => {
    const now = performance.now();
    webrtc.sendKeyEvent(0x00, true);  // Dummy event with timestamp
};

// 서버 측: 타임스탬프 수신 → 비디오에 오버레이
// Sunshine에서 타임스탬프를 화면에 그림 → 브라우저에서 감지 → RTT 계산
```

#### Stats 수집
```typescript
// WebRTC Stats API
setInterval(async () => {
    const stats = await pc.getStats();
    stats.forEach(report => {
        if (report.type === 'inbound-rtp' && report.kind === 'video') {
            console.log(`
                Bitrate: ${report.bytesReceived * 8 / 1000} kbps
                Framerate: ${report.framesPerSecond} fps
                Packets Lost: ${report.packetsLost}
                Jitter: ${report.jitter} ms
            `);
        }
    });
}, 1000);
```

### 4.2. 최적화 체크리스트

#### 네트워크 최적화
- [ ] BBR congestion control 활성화
- [ ] UDP 버퍼 크기 증가 (25MB)
- [ ] MTU 최적화 (Jumbo Frames, 9000 bytes)
- [ ] QoS 설정 (DSCP marking)

#### 인코딩 최적화
- [ ] NVENC Preset: P1 (ultrafast)
- [ ] GOP Length: 60 (1초)
- [ ] B-Frames: 0
- [ ] Slicing: 1 slice per frame
- [ ] Rate Control: CBR
- [ ] Bitrate: Adaptive (10-50Mbps)

#### 디코딩 최적화
- [ ] Hardware decode 활성화 (`<video>` 태그)
- [ ] WebGL 렌더링 (Canvas)
- [ ] Double buffering
- [ ] VSync off (지연시간 우선)

#### 입력 최적화
- [ ] Input polling rate: 1000Hz
- [ ] Pointer Lock API (마우스 정밀도)
- [ ] Keyboard raw input (브라우저 이벤트 바이패스)

---

## 📦 Phase 5: 프로덕션 배포 (1주)

### 5.1. Slurm 통합

⚠️ **중요**: 기존 `backend_5010/vnc_api.py`를 절대 수정하지 않음!

#### 새 파일 생성: moonlight_api.py

**완전히 독립된 백엔드 디렉토리**로 작성:

```bash
# 새 백엔드 디렉토리 구조 ({purpose}_{port} 패턴)
backend_moonlight_8004/              # ✅ backend_5010/과 완전 분리
├── app.py                           # Flask 메인 앱
├── moonlight_api.py                 # Moonlight API Blueprint
├── requirements.txt                 # Python 의존성
├── gunicorn_config.py               # Gunicorn 설정 (Port 8004)
├── logs/                            # 독립 로그 디렉토리
└── venv/                            # 독립 가상환경
```

```python
# backend_moonlight_8004/moonlight_api.py
"""
Moonlight/Sunshine Session Management API
❌ backend_5010/vnc_api.py를 수정하지 않음!
✅ 완전히 독립된 새 파일
"""

from flask import Blueprint, request, jsonify, g
from middleware.jwt_middleware import jwt_required, group_required
import subprocess
import random
import time

moonlight_bp = Blueprint('moonlight', __name__, url_prefix='/api/moonlight')

# Moonlight 전용 설정
SUNSHINE_IMAGES_DIR = "/opt/apptainers"
SUNSHINE_SANDBOXES_DIR = "/scratch/sunshine_sandboxes"  # ✅ VNC와 분리
SUNSHINE_SESSIONS_DIR = "/scratch/sunshine_sessions"
SUNSHINE_LOG_DIR = "/scratch/sunshine_logs"

# Sunshine 이미지 목록 (VNC와 완전 독립)
SUNSHINE_IMAGES = {
    "xfce4": {
        "name": "XFCE4 Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_xfce4.sif",  # ✅ 새 이미지
        "icon": "🌞",
        "default": True
    },
    "gnome": {
        "name": "GNOME Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_gnome.sif",  # ✅ 새 이미지
        "icon": "🎨",
        "default": False
    }
}

def submit_moonlight_job(username, session_id, sunshine_port, geometry, duration_hours, sif_image_path, image_id):
    """Moonlight 전용 Slurm Job 제출 (VNC와 독립)"""

    script = f"""#!/bin/bash
#SBATCH --job-name=moonlight-{username}
#SBATCH --partition=viz
#SBATCH --qos=moonlight         # ✅ QoS로 리소스 격리
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time={duration_hours}:00:00
#SBATCH --output={SUNSHINE_LOG_DIR}/moonlight-{username}-%j.out
#SBATCH --error={SUNSHINE_LOG_DIR}/moonlight-{username}-%j.err

# 로그 디렉토리 생성
mkdir -p {SUNSHINE_LOG_DIR}

echo "========================================"
echo "Moonlight/Sunshine Session Starting"
echo "User: {username}"
echo "Session ID: {session_id}"
echo "Sunshine Port: {sunshine_port}"
echo "Image: {sif_image_path}"
echo "Node: $(hostname)"
echo "========================================"

# Sunshine 전용 Sandbox (VNC와 완전 분리)
SANDBOX_BASE={SUNSHINE_SANDBOXES_DIR}
USER_SANDBOX=$SANDBOX_BASE/{username}_{image_id}
INSTANCE_NAME="moonlight-{username}-{image_id}"

# Sandbox 생성 또는 재사용
if [ ! -d "$USER_SANDBOX" ]; then
    echo "Creating Sunshine sandbox for {username}..."
    mkdir -p $SANDBOX_BASE
    apptainer build --sandbox $USER_SANDBOX {sif_image_path}
    echo "Sunshine sandbox created at $USER_SANDBOX"
else
    echo "Using existing Sunshine sandbox at $USER_SANDBOX"
fi

# 기존 Instance 정리
if apptainer instance list | grep -q $INSTANCE_NAME; then
    echo "Stopping existing Sunshine instance..."
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    sleep 2
fi

# Apptainer Instance 시작
echo "Starting Sunshine instance: $INSTANCE_NAME"
apptainer instance start --writable --nv --home $USER_SANDBOX/home/{username}:/home/{username} $USER_SANDBOX $INSTANCE_NAME

# X11 Display 시작 (Sunshine용)
DISPLAY_NUM=10  # VNC는 :1~:9 사용, Sunshine은 :10부터 사용
echo "Starting X11 display :$DISPLAY_NUM for Sunshine..."
apptainer exec instance://$INSTANCE_NAME Xvfb :$DISPLAY_NUM -screen 0 {geometry}x24 &
sleep 2

# Desktop Environment 시작
export DISPLAY=:$DISPLAY_NUM
apptainer exec --cleanenv instance://$INSTANCE_NAME /bin/bash -c "DISPLAY=:$DISPLAY_NUM startxfce4" &
sleep 5

# Sunshine 시작
echo "Starting Sunshine on port {sunshine_port}..."
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "
    export DISPLAY=:$DISPLAY_NUM
    export CUDA_VISIBLE_DEVICES=0
    export NVIDIA_VISIBLE_DEVICES=0
    mkdir -p /home/{username}/.config/sunshine
    sunshine --port {sunshine_port} --config /home/{username}/.config/sunshine/sunshine.conf
" &

echo "Sunshine session ready!"
echo "========================================"

# Cleanup handler
cleanup() {{
    echo "Terminating Sunshine session..."
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    echo "Sunshine session terminated"
}}

trap cleanup EXIT INT TERM

# Wait
echo "Sunshine session is running. Press Ctrl+C or scancel to terminate."
while true; do
    if ! apptainer instance list | grep -q $INSTANCE_NAME; then
        echo "ERROR: Instance stopped unexpectedly"
        exit 1
    fi
    sleep 10
done
"""

    # Slurm Job 제출
    script_path = f"/tmp/moonlight_job_{session_id}.sh"
    with open(script_path, 'w') as f:
        f.write(script)

    result = subprocess.run(
        ['sbatch', script_path],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        raise Exception(f"Job submission failed: {result.stderr}")

    job_id = int(result.stdout.strip().split()[-1])
    return job_id


@moonlight_bp.route('/sessions', methods=['POST'])
@jwt_required
@group_required('HPC-Admins', 'HPC-Users', 'GPU-Users')
def create_moonlight_session():
    """Moonlight 세션 생성 (VNC와 완전 독립)"""

    user = g.user
    data = request.json or {}

    image_id = data.get('image_id', 'xfce4')
    geometry = data.get('geometry', '1920x1080')
    duration_hours = int(data.get('duration_hours', 4))

    # Sunshine 포트 할당 (VNC 포트와 겹치지 않음)
    sunshine_port = random.randint(47989, 47999)

    # 세션 ID (Moonlight 전용 prefix)
    timestamp = int(time.time())
    session_id = f"ml-{user['username']}-{timestamp}"  # ✅ "ml-" prefix

    # Slurm Job 제출
    job_id = submit_moonlight_job(
        user['username'],
        session_id,
        sunshine_port,
        geometry,
        duration_hours,
        SUNSHINE_IMAGES[image_id]['sif_path'],
        image_id
    )

    # Redis에 저장 (Moonlight 전용 키)
    session_data = {
        'session_id': session_id,
        'job_id': job_id,
        'username': user['username'],
        'image_id': image_id,
        'sunshine_port': sunshine_port,
        'geometry': geometry,
        'status': 'pending'
    }

    # Redis key: moonlight:session:{session_id}  ✅ VNC와 분리
    redis_client.set(f'moonlight:session:{session_id}', json.dumps(session_data), ex=duration_hours*3600)

    return jsonify(session_data), 201


# ... 나머지 API endpoints (list, get, delete)
```

**✅ 핵심 차이점**:
1. **완전히 새 파일**: `MoonlightSunshine_8004/backend/moonlight_api.py`
2. **VNC 코드 건드리지 않음**: `backend_5010/vnc_api.py`는 그대로 유지
3. **독립된 경로**: `/scratch/sunshine_*` (VNC는 `/scratch/vnc_*`)
4. **독립된 Redis 키**: `moonlight:session:*` (VNC는 `vnc:session:*`)
5. **독립된 Slurm QoS**: `--qos=moonlight`
6. **독립된 Display 번호**: `:10` (VNC는 `:1~:9`)

### 5.2. Nginx 설정

⚠️ **중요**: 기존 `/etc/nginx/conf.d/auth-portal.conf`를 수정 (새 파일 생성 ❌)

**이유**:
- 기존 파일이 이미 `listen 443 ssl http2;` 사용 중
- 별도 파일로 만들면 "duplicate listen" 에러 발생
- **해결**: 기존 파일 내부에 `location` 블록만 추가

```nginx
# ❌ 잘못된 방법: 별도 파일 생성
# /etc/nginx/conf.d/moonlight.conf (이렇게 하지 말 것!)
server {
    listen 443 ssl http2;  # ❌ auth-portal.conf와 충돌!
}
```

```nginx
# ✅ 올바른 방법: 기존 파일에 추가
# /etc/nginx/conf.d/auth-portal.conf 수정

# 파일 상단에 upstream 추가
upstream moonlight_backend {
    server 127.0.0.1:8004;
}

upstream moonlight_signaling {
    server 127.0.0.1:8005;
}

# 기존 server 블록 내부에 location 추가
server {
    listen 443 ssl http2;
    server_name _;

    # ========== 기존 VNC 설정 (유지) ==========
    location /vnc {
        alias /var/www/html/vnc_service_8002;
        try_files $uri $uri/ /vnc/index.html;
    }

    location ~ ^/vncproxy/([0-9]+)/(.*)$ {
        proxy_pass http://127.0.0.1:$1/$2$is_args$args;
        # ... (기존 설정 유지)
    }

    # ========== 신규 Moonlight 설정 (추가) ==========
    # Moonlight Frontend (Static Files)
    location /moonlight/ {
        alias /var/www/html/moonlight_8004/;
        try_files $uri $uri/ /moonlight/index.html;
        index index.html;

        gzip on;
        gzip_types text/plain text/css application/json application/javascript;

        # Prevent caching for index.html
        location = /moonlight/index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
        }
    }

    # Moonlight API (HTTP)
    location /api/moonlight/ {
        proxy_pass http://moonlight_backend/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers (개발용, 프로덕션에서는 제거)
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, DELETE, OPTIONS";
    }

    # WebRTC Signaling (WebSocket)
    location /moonlight/signaling {
        proxy_pass http://moonlight_signaling;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # WebSocket specific
        proxy_read_timeout 86400s;  # 24시간
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }

    # 기존 설정 계속...
}
```

**적용 방법**:
```bash
# 1. 기존 파일 백업
sudo cp /etc/nginx/conf.d/auth-portal.conf /etc/nginx/conf.d/auth-portal.conf.backup_$(date +%Y%m%d_%H%M%S)

# 2. 파일 수정 (vi 또는 nano)
sudo vi /etc/nginx/conf.d/auth-portal.conf
# 위 내용 추가

# 3. 문법 검사
sudo nginx -t
# Expected: syntax is ok

# 4. Nginx 재시작
sudo systemctl reload nginx
```

### 5.3. Systemd Service

```ini
# /etc/systemd/system/moonlight-gateway.service
[Unit]
Description=Moonlight/Sunshine WebRTC Gateway
After=network.target

[Service]
Type=simple
User=koopark
WorkingDirectory=/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
ExecStart=/usr/bin/node backend/server.js
Restart=always
RestartSec=10

Environment=NODE_ENV=production
Environment=PORT=8004

[Install]
WantedBy=multi-user.target
```

---

## 📊 예상 성능 지표

| 항목 | 현재 (VNC) | Moonlight/Sunshine | 개선율 |
|------|-----------|-------------------|--------|
| **지연시간** | 50-210ms | 5-20ms | **90%** |
| **최대 해상도** | 1920x1080@60fps | 3840x2160@120fps | **4배** |
| **비트레이트** | 5-10Mbps | 10-50Mbps (adaptive) | **3배** |
| **CPU 사용률** (viz-node) | 40-60% | 5-10% (NVENC) | **85% 감소** |
| **네트워크 대역폭** | 고정 | 동적 조정 | 효율 **70%↑** |
| **색심도** | 8-bit | 10-bit HDR 지원 | ✅ |
| **오디오** | 없음 | 48kHz stereo | ✅ |

---

## 🎯 마일스톤

### Week 1-2: 기반 구축
- [x] Sunshine 설치 및 NVENC 설정
- [x] 네트워크 최적화 (BBR, UDP buffer)
- [ ] 기본 스트리밍 테스트 (Moonlight native client)

### Week 3-4: WebRTC Gateway
- [ ] Node.js Signaling Server 구현
- [ ] Sunshine GameStream Bridge
- [ ] STUN/TURN 서버 설정 (coturn)

### Week 5-6: Web Client
- [ ] React 프론트엔드 구현
- [ ] WebRTC Handler
- [ ] Hardware Decode + Canvas Rendering
- [ ] Input Forwarder

### Week 7-8: 통합 및 최적화
- [ ] Slurm 통합
- [ ] Redis 세션 관리
- [ ] 성능 측정 및 튜닝
- [ ] 지연시간 5ms 이하 달성

### Week 9: 프로덕션 배포
- [ ] Nginx 리버스 프록시 설정
- [ ] Systemd 서비스 등록
- [ ] 모니터링 (Prometheus)
- [ ] 문서화 및 사용자 가이드

---

## 🔧 개발 환경 요구사항

### viz-node (Compute Node)
- NVIDIA GPU (GTX 1060 이상, NVENC 지원)
- NVIDIA Driver 520.xx 이상
- CUDA 11.8+
- Sunshine 0.20.0+
- Ubuntu 22.04 LTS

### Controller (Headnode)
- Node.js 18.x
- Redis 7.x
- coturn (STUN/TURN)
- Nginx 1.24+

### 브라우저 요구사항
- Chrome/Edge 90+ (Hardware H.264 decode)
- Firefox 88+ (Software decode fallback)
- Safari 14+ (macOS only)

---

## 📚 참고 자료

- **Sunshine**: https://github.com/LizardByte/Sunshine
- **Moonlight**: https://github.com/moonlight-stream
- **NVENC Programming Guide**: https://developer.nvidia.com/nvidia-video-codec-sdk
- **WebRTC Samples**: https://webrtc.github.io/samples/
- **GameStream Protocol**: https://github.com/moonlight-stream/moonlight-docs

---

## 🚀 최종 목표

**"마치 로컬 머신처럼" - 5ms 이하의 지연시간으로 4K 해상도의 리눅스 데스크톱을 웹 브라우저에서 실시간으로 조작**

이 시스템이 완성되면:
- CAE 엔지니어가 웹 브라우저에서 LS-PrePost를 마치 로컬처럼 사용
- 마우스 클릭, 3D 회전, 줌 등이 즉각 반응 (5-20ms)
- 4K 모니터에서도 선명한 화질 유지
- 네트워크 상황에 따라 자동으로 품질 조정 (Adaptive Bitrate)
- 기존 VNC 서비스는 fallback으로 유지

**Let's build the future of remote HPC visualization! 🎮🖥️**
