# VNC Desktop 환경 문제 해결 가이드

## 개요

Apptainer 기반 VNC 데스크톱 환경(XFCE4, GNOME)에서 발생한 문제들과 해결 방법을 정리한 문서입니다.

**작성일**: 2025-10-18
**환경**: Ubuntu 22.04, Slurm HPC, Apptainer/Singularity, TigerVNC

---

## 목차

1. [XFCE4 검은 화면 문제 해결](#xfce4-검은-화면-문제-해결)
2. [GNOME 실행 실패 문제 해결](#gnome-실행-실패-문제-해결)
3. [공통 설정 및 최종 구조](#공통-설정-및-최종-구조)

---

## XFCE4 검은 화면 문제 해결

### 문제 증상

- VNC로 XFCE4에 접속하면 **검은 화면**만 표시됨
- `xfce4-session` 프로세스가 시작되지 않음
- 로그에 `xfce4-session: Another session manager is already running` 에러 발생

### 근본 원인 분석

#### 1. ICE-unix Socket 파일 충돌

**문제**: Apptainer instance가 호스트의 `/tmp`를 바인드 마운트하면서 이전 세션의 socket 파일들이 누적됨

```bash
# Instance 내부에서 확인
apptainer exec instance://vnc-admin-xfce4 ls -la /tmp/.ICE-unix/

# 결과: 수십 개의 오래된 socket 파일
srwxrwxrwx  1 koopark koopark     0 Oct 18 00:03 105
srwxrwxrwx  1 koopark koopark     0 Oct 18 15:28 14
srwxrwxrwx  1 koopark koopark     0 Oct 18 16:11 15
... (총 11개)
```

XFCE4는 ICE (Inter-Client Exchange) 프로토콜을 사용하는데, 이 socket 파일들이 남아있으면 "세션이 이미 실행 중"이라고 판단합니다.

#### 2. DISPLAY 환경변수 손실

**문제**: `dbus-launch` 실행 후 `DISPLAY` 환경변수가 사라짐

```bash
# 원래 스크립트
export DISPLAY=:${DISPLAY_NUM}
eval $(dbus-launch --sh-syntax)
exec xfce4-session  # DISPLAY가 비어있음!
```

#### 3. Instance 내부에서 pkill 작동 안 함

**문제**: Instance 내부에서 실행한 bash 프로세스는 다른 프로세스를 kill할 권한이 없음

```bash
# 시도한 방법 (실패)
apptainer exec instance://vnc-admin-xfce4 pkill -9 xfce4-screensaver
# → 프로세스가 죽지 않음!
```

### 해결 방법

#### 1. `--cleanenv` 플래그 사용 (핵심 해결책)

백업 폴더(`KooSlurmInstallAutomationRefactory_V5.5.1`)의 작동하던 설정에서 발견한 핵심:

**위치**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/vnc_api.py:189`

```python
# 수정 전
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "..."

# 수정 후
apptainer exec --cleanenv instance://$INSTANCE_NAME /bin/bash -c "..."
```

**효과**:
- 호스트의 모든 환경변수를 제거
- 깨끗한 환경에서 VNC 세션 시작
- D-Bus, ICE 등의 세션 충돌 방지

#### 2. Instance 시작 후 Socket 파일 정리

**위치**: `vnc_api.py:183-185`

```python
# Apptainer Instance 시작 (지속적 실행)
apptainer instance start --writable --nv $USER_SANDBOX $INSTANCE_NAME

# Instance 내부에서 세션 소켓 파일 정리 (매우 중요!)
echo "Cleaning up session socket files inside instance..."
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "rm -rf /tmp/.ICE-unix/* /tmp/.X11-unix/* /tmp/.X*-lock 2>/dev/null || true"
```

**중요**: Sandbox 디렉토리의 `/tmp`를 정리해도 소용없습니다! Instance 내부의 `/tmp`는 **호스트의 /tmp**를 바인드 마운트하기 때문에, instance 시작 후에 정리해야 합니다.

#### 3. Instance 재시작 전 프로세스 정리

**위치**: `vnc_api.py:157-177`

```bash
# 기존 Instance가 있으면 중지 (완전히 재시작)
if apptainer instance list | grep -q $INSTANCE_NAME; then
    echo "Stopping existing instance and killing all processes..."
    # Instance 내부의 모든 VNC/XFCE 프로세스 강제 종료
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-session 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-panel 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfwm4 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfdesktop 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-screensaver 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfconfd 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 dbus-daemon 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 dbus-launch 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 Xtigervnc 2>/dev/null || true
    sleep 2
    # Instance 종료
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    sleep 2
fi
```

#### 4. XFCE4 시작 스크립트 단순화

**위치**: `/scratch/vnc_sandboxes/admin_xfce4/opt/scripts/start_vnc.sh`

```bash
#!/bin/bash
# VNC + XFCE4 시작 스크립트

# 호스트 DBUS 환경변수 제거 (가장 중요!)
unset DBUS_SESSION_BUS_ADDRESS
unset DBUS_SESSION_BUS_PID

# VNC Display 번호 (파라미터로 받거나 기본값 사용)
DISPLAY_NUM=${1:-1}
export DISPLAY=:${DISPLAY_NUM}
export XAUTHORITY=/root/.Xauthority

# XDG 환경 설정
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR

# Xtigervnc 시작 (백그라운드)
echo "Starting Xtigervnc on display :${DISPLAY_NUM}"
Xtigervnc :${DISPLAY_NUM} \
    -geometry ${VNC_GEOMETRY:-1920x1080} \
    -depth 24 \
    -rfbport ${VNC_PORT:-5900} \
    -SecurityTypes None \
    -AlwaysShared \
    -AcceptKeyEvents \
    -AcceptPointerEvents \
    -AcceptSetDesktopSize \
    -SendCutText \
    -AcceptCutText \
    -desktop "VNC Desktop" \
    -localhost no \
    > /tmp/Xtigervnc_${DISPLAY_NUM}.log 2>&1 &

VNC_PID=$!
echo "Xtigervnc started with PID: $VNC_PID"

# X 서버가 시작될 때까지 대기
sleep 3

# XFCE4 세션 시작 (startxfce4 사용 - 간단!)
echo "Starting XFCE4 with startxfce4"
exec startxfce4
```

**핵심 변경점**:
- ❌ 제거: `dbus-launch` 수동 실행
- ❌ 제거: `xfce4-session` 직접 실행
- ✅ 사용: `startxfce4` (XFCE4 전체를 올바른 순서로 시작)

### 왜 이 방법이 작동하는가?

1. **`--cleanenv`**: 호스트 환경변수 충돌을 완전히 제거
2. **Socket 파일 정리**: 이전 세션 흔적 제거
3. **`startxfce4`**: D-Bus, window manager, panel 등을 올바른 순서로 자동 시작
4. **Instance 재시작**: 완전히 깨끗한 상태에서 시작

---

## GNOME 실행 실패 문제 해결

### 문제 증상

- GNOME VNC 세션이 시작되지 않음
- 로그에 systemd 관련 에러 발생:
  ```
  gnome-session-binary: ERROR: Failed to connect to system bus: Could not connect: No such file or directory
  ```
- VNC 화면이 검은색 또는 연결 실패

### 근본 원인 분석

#### GNOME의 systemd 의존성

GNOME은 **systemd system bus**에 의존합니다:

```
gnome-session-binary[21]: WARNING: Failed to upload environment to systemd:
  GDBus.Error:org.freedesktop.DBus.Error.NameHasNoOwner:
  Name "org.freedesktop.systemd1" does not exist

gnome-session-binary[21]: ERROR: Failed to connect to system bus:
  Could not connect: No such file or directory
aborting...
```

**문제점**:
- GNOME은 systemd를 통해 세션 관리, 환경변수 업로드, 서비스 시작 등을 수행
- Apptainer 환경에는 systemd가 없음
- System bus (`/var/run/dbus/system_bus_socket`)가 존재하지 않음

**XFCE4와의 차이**:
- XFCE4: systemd 없이도 작동 가능 (전통적인 X session 방식)
- GNOME: systemd 통합이 깊게 되어 있음 (Ubuntu 18.04 이후)

### 시도했던 실패한 방법들

#### 1. GNOME Classic 모드 시도 (실패)

```bash
exec gnome-session --session=gnome-classic
```
→ 여전히 system bus 에러 발생

#### 2. GNOME 컴포넌트 개별 실행 (실패)

```bash
/usr/libexec/gnome-settings-daemon &
gnome-panel &
nautilus --no-default-window &
exec metacity
```
→ Metacity가 설치되어 있지 않음, 컴포넌트 간 통신 실패

#### 3. Acceleration check 비활성화만 (실패)

```bash
exec gnome-session --session=ubuntu --disable-acceleration-check
```
→ System bus 문제는 해결되지 않음

### 해결 방법

#### D-Bus System Bus Workaround (성공!)

**핵심 아이디어**: Session bus를 system bus로도 사용하도록 속이기

**위치**: `/scratch/vnc_sandboxes/admin_gnome/opt/scripts/start_vnc_gnome.sh`

```bash
#!/bin/bash
# VNC + GNOME 시작 스크립트 (D-Bus system bus workaround)

# 호스트 DBUS 환경변수 제거
unset DBUS_SESSION_BUS_ADDRESS
unset DBUS_SESSION_BUS_PID
unset SESSION_MANAGER

# VNC Display 번호
DISPLAY_NUM=${1:-1}
export DISPLAY=:${DISPLAY_NUM}
export XAUTHORITY=/root/.Xauthority

# XDG 환경 설정
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=GNOME
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR

# Xtigervnc 시작
echo "Starting Xtigervnc on display :${DISPLAY_NUM}"
Xtigervnc :${DISPLAY_NUM} \
    -geometry ${VNC_GEOMETRY:-1920x1080} \
    -depth 24 \
    -rfbport ${VNC_PORT:-5900} \
    -SecurityTypes None \
    -AlwaysShared \
    -AcceptKeyEvents \
    -AcceptPointerEvents \
    -AcceptSetDesktopSize \
    -SendCutText \
    -AcceptCutText \
    -desktop "GNOME Desktop" \
    -localhost no \
    > /tmp/Xtigervnc_${DISPLAY_NUM}.log 2>&1 &

VNC_PID=$!
echo "Xtigervnc started with PID: $VNC_PID"

# X 서버 시작 대기
sleep 3

# ====== 핵심 해결책: D-Bus system bus workaround ======
echo "Starting D-Bus session bus (with system bus workaround)"
mkdir -p /var/run/dbus

# D-Bus session bus 시작
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

# Session bus를 system bus로도 사용하도록 설정
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS

echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
echo "DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SYSTEM_BUS_ADDRESS"

# DISPLAY 다시 설정 (dbus-launch가 덮어쓸 수 있음)
export DISPLAY=:${DISPLAY_NUM}

# GNOME session을 systemd 모드로 시작
echo "Starting GNOME session in systemd mode"
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_CLASS=user
exec gnome-session --session=ubuntu --systemd --debug 2>&1
```

### 핵심 해결 포인트

#### 1. D-Bus System Bus Address 설정

```bash
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
```

**효과**:
- GNOME이 system bus를 요구할 때 실제로는 session bus를 사용
- systemd가 없어도 GNOME이 D-Bus 통신 가능
- `org.freedesktop.systemd1` 서비스 검색 실패는 무시되고 fallback 모드로 진행

#### 2. `--systemd` 플래그 사용

```bash
exec gnome-session --session=ubuntu --systemd --debug 2>&1
```

**이유**:
- GNOME에게 "systemd를 사용하려 시도하라"고 알림
- System bus를 찾을 때 우리가 설정한 fake system bus 사용
- Fallback 모드로 전환되면서도 대부분의 GNOME 기능 작동

#### 3. 환경변수 설정

```bash
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_CLASS=user
```

**효과**:
- Ubuntu 기본 GNOME 세션 사용
- 사용자 세션으로 인식 (시스템 세션이 아님)

### 왜 이 방법이 작동하는가?

#### GNOME의 D-Bus 통신 구조

```
GNOME Session Manager
    ↓ (system bus 요청)
DBUS_SYSTEM_BUS_ADDRESS → unix:abstract=/tmp/dbus-xxxxx
                                      ↓
                            실제로는 session bus!
```

#### Fallback 메커니즘 활용

GNOME은 다음과 같은 fallback 로직을 가지고 있습니다:

1. System bus 연결 시도
2. 실패 시 "Falling back to non-systemd startup procedure" 경고
3. 일부 기능은 비활성화되지만 **기본 데스크톱 환경은 작동**

우리의 workaround는 이 fallback을 우아하게 작동시킵니다:
- System bus 주소는 설정되어 있음 (연결 시도 가능)
- Systemd 서비스는 없지만 D-Bus 통신은 가능
- 필수 컴포넌트들은 정상 시작

### Backend 설정 차이점

GNOME과 XFCE4는 별도의 설정을 사용합니다:

**위치**: `vnc_api.py:52-72`

```python
VNC_IMAGES = {
    "xfce4": {
        "name": "XFCE4 Desktop",
        "description": "Lightweight desktop environment with XFCE4",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_desktop.sif",
        "start_script": "/opt/scripts/start_vnc.sh",
        "desktop_env": "XFCE4",
        "icon": "🖥️",
        "default": True
    },
    "gnome": {
        "name": "GNOME Desktop",
        "description": "Full-featured Ubuntu GNOME desktop environment",
        "sif_path": f"{VNC_IMAGES_DIR}/vnc_gnome.sif",
        "start_script": "/opt/scripts/start_vnc_gnome.sh",
        "desktop_env": "GNOME",
        "icon": "🎨",
        "default": False
    }
}
```

**Job Script 생성 시**:

```python
# Line 138-139
USER_SANDBOX=$SANDBOX_BASE/{username}_{image_id}
INSTANCE_NAME="vnc-{username}-{image_id}"
```

- XFCE4: `admin_xfce4`, `vnc-admin-xfce4`
- GNOME: `admin_gnome`, `vnc-admin-gnome`

---

## 공통 설정 및 최종 구조

### Backend VNC API 핵심 설정

#### 1. `--cleanenv` 플래그 (양쪽 공통)

**위치**: `vnc_api.py:189`

```python
apptainer exec --cleanenv instance://$INSTANCE_NAME /bin/bash -c "VNC_PORT={vnc_port} VNC_GEOMETRY={geometry} {start_script} {display_num}"
```

#### 2. Instance 재시작 로직 (양쪽 공통)

**위치**: `vnc_api.py:157-181`

```bash
# 기존 Instance가 있으면 중지 (완전히 재시작)
if apptainer instance list | grep -q $INSTANCE_NAME; then
    # 모든 데스크톱 프로세스 강제 종료
    apptainer exec instance://$INSTANCE_NAME pkill -9 xfce4-session 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 gnome-session 2>/dev/null || true
    apptainer exec instance://$INSTANCE_NAME pkill -9 gnome-shell 2>/dev/null || true
    # ... 기타 프로세스들

    # Instance 종료
    apptainer instance stop $INSTANCE_NAME 2>/dev/null || true
    sleep 2
fi

# Instance 시작
apptainer instance start --writable --nv $USER_SANDBOX $INSTANCE_NAME

# Socket 파일 정리
apptainer exec instance://$INSTANCE_NAME /bin/bash -c "rm -rf /tmp/.ICE-unix/* /tmp/.X11-unix/* /tmp/.X*-lock 2>/dev/null || true"
```

### 디렉토리 구조

```
/scratch/
├── apptainers/
│   ├── vnc_desktop.sif          # XFCE4 이미지
│   └── vnc_gnome.sif            # GNOME 이미지
└── vnc_sandboxes/
    ├── admin_xfce4/             # XFCE4 sandbox
    │   └── opt/scripts/
    │       └── start_vnc.sh
    └── admin_gnome/             # GNOME sandbox
        └── opt/scripts/
            └── start_vnc_gnome.sh
```

### Slurm Job Script 흐름

```bash
1. Sandbox 존재 확인 및 생성
   ↓
2. 기존 Instance 중지 (있다면)
   ↓
3. Instance 프로세스 강제 종료
   ↓
4. Instance 재시작
   ↓
5. Socket 파일 정리
   ↓
6. VNC + Desktop 시작 (--cleanenv)
   ↓
7. noVNC websockify 시작
   ↓
8. 세션 유지 (무한 루프)
```

---

## 문제 해결 체크리스트

### XFCE4가 검은 화면일 때

- [ ] `--cleanenv` 플래그가 적용되어 있는가?
- [ ] Instance 시작 후 socket 파일을 정리하는가?
- [ ] `startxfce4` 명령어를 사용하는가?
- [ ] Backend가 최신 코드로 재시작되었는가?

### GNOME이 시작되지 않을 때

- [ ] `DBUS_SYSTEM_BUS_ADDRESS`가 설정되어 있는가?
- [ ] `gnome-session --systemd` 플래그를 사용하는가?
- [ ] 올바른 sandbox (`admin_gnome`)를 사용하는가?
- [ ] 올바른 스크립트 (`start_vnc_gnome.sh`)를 실행하는가?

### 공통 체크사항

- [ ] Apptainer instance가 제대로 시작되었는가?
  ```bash
  apptainer instance list
  ```
- [ ] VNC 로그에 에러가 있는가?
  ```bash
  cat /tmp/vnc_admin_*.log
  ```
- [ ] Backend 로그를 확인했는가?
  ```bash
  tail -100 /tmp/backend_final.log
  ```

---

## 참고 자료

### 관련 파일

- Backend API: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/vnc_api.py`
- XFCE4 Script: `/scratch/vnc_sandboxes/admin_xfce4/opt/scripts/start_vnc.sh`
- GNOME Script: `/scratch/vnc_sandboxes/admin_gnome/opt/scripts/start_vnc_gnome.sh`

### 유용한 명령어

```bash
# VNC job 확인
squeue -u koopark | grep vnc

# Instance 목록
ssh koopark@192.168.122.252 "apptainer instance list"

# VNC 로그 확인
ssh koopark@192.168.122.252 "ls -lt /tmp/vnc_admin_*.log | head -1"
ssh koopark@192.168.122.252 "cat /tmp/vnc_admin_XX.log"

# Instance 내부 프로세스 확인
ssh koopark@192.168.122.252 "apptainer exec instance://vnc-admin-xfce4 ps aux"
ssh koopark@192.168.122.252 "apptainer exec instance://vnc-admin-gnome ps aux"

# Socket 파일 확인
ssh koopark@192.168.122.252 "apptainer exec instance://vnc-admin-xfce4 ls -la /tmp/.ICE-unix/"

# Backend 재시작
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010
lsof -i :5010 | grep LISTEN | awk '{print $2}' | xargs -r kill -9
source venv/bin/activate
python3 app.py > /tmp/backend.log 2>&1 &
```

---

## 결론

### XFCE4 해결의 핵심

1. **`--cleanenv`**: 환경변수 충돌 제거
2. **Socket 파일 정리**: Instance 시작 후 `/tmp/.ICE-unix/*` 제거
3. **`startxfce4`**: 올바른 순서로 모든 컴포넌트 시작

### GNOME 해결의 핵심

1. **D-Bus System Bus Workaround**: Session bus를 system bus로 사용
2. **`--systemd` 플래그**: Systemd 모드로 시작하되 fallback 허용
3. **환경변수 설정**: GNOME에게 올바른 세션 정보 제공

### 교훈

- Apptainer 환경에서는 호스트 시스템과의 차이를 이해해야 함
- 데스크톱 환경마다 요구사항이 다름 (XFCE4: 단순, GNOME: systemd 의존)
- 백업/작동하던 설정을 참고하는 것이 중요 (`--cleanenv` 발견)
- 로그를 자세히 읽고 근본 원인을 파악해야 함

---

**문서 버전**: 1.0
**최종 수정**: 2025-10-18
**작성자**: Claude AI Assistant
