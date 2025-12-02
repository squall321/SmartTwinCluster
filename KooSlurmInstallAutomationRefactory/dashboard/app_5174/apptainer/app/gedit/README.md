# GEdit Apptainer Container

GEdit 텍스트 에디터를 VNC를 통해 웹 브라우저에서 실행할 수 있는 Apptainer 컨테이너입니다.

## 📦 포함된 구성요소

- **GEdit**: GNOME 텍스트 에디터
- **TigerVNC**: VNC 서버
- **websockify**: noVNC용 WebSocket 프록시
- **XFCE4**: 경량 데스크톱 환경

## 🔨 빌드 방법

```bash
# 빌드 스크립트 사용
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/apptainer/app
./build.sh

# 또는 직접 빌드
cd gedit
sudo apptainer build --force gedit.sif gedit.def
```

## 🚀 실행 방법

### 기본 실행
```bash
apptainer run gedit.sif
```

### 포트 설정
```bash
apptainer run \
    --env VNC_PORT=5901 \
    --env WEBSOCKIFY_PORT=6080 \
    gedit.sif
```

### 해상도 설정
```bash
apptainer run \
    --env VNC_RESOLUTION=1920x1080 \
    --env VNC_DEPTH=24 \
    gedit.sif
```

## 🌐 접속 방법

### VNC 클라이언트로 접속
```bash
vncviewer localhost:5901
```

### noVNC (웹 브라우저)로 접속
```
http://localhost:6080/vnc.html
```

### App Framework에서 사용
app_5174 프레임워크에서 자동으로 WebSocket 연결:
```
ws://localhost:6080
```

## 🔧 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `DISPLAY` | `:1` | X Display 번호 |
| `VNC_RESOLUTION` | `1280x720` | VNC 화면 해상도 |
| `VNC_DEPTH` | `24` | 색상 깊이 (bit) |
| `VNC_PORT` | `5901` | VNC 서버 포트 |
| `WEBSOCKIFY_PORT` | `6080` | WebSocket 프록시 포트 |

## 📁 파일 구조

```
gedit/
├── gedit.def           # Apptainer 정의 파일
├── start-gedit.sh      # 시작 스크립트
├── supervisord.conf    # Supervisor 설정
└── README.md           # 이 문서
```

## 🐛 트러블슈팅

### VNC 서버가 시작되지 않음
```bash
# 로그 확인
apptainer exec gedit.sif cat /tmp/vncserver.log
```

### 포트 충돌
```bash
# 다른 포트 사용
apptainer run --env VNC_PORT=5902 --env WEBSOCKIFY_PORT=6081 gedit.sif
```

### 권한 문제
```bash
# 샌드박스 모드로 실행
sudo apptainer build --sandbox gedit_sandbox gedit.def
sudo apptainer shell --writable gedit_sandbox
```

## 📝 로그 위치

컨테이너 내부:
- VNC 서버: `/root/.vnc/*.log`
- GEdit: `/tmp/gedit.*.log`
- Supervisor: `/tmp/supervisord.log`

## ⚙️ 커스터마이징

### 다른 에디터 사용
`start-gedit.sh`에서 gedit을 다른 프로그램으로 변경:
```bash
# gedit 대신 vim 실행
DISPLAY=$DISPLAY xterm -e vim &
```

### 추가 패키지 설치
`gedit.def`의 `%post` 섹션에 추가:
```
apt-get install -y your-package
```

## 🔗 관련 문서

- [Apptainer Documentation](https://apptainer.org/docs/)
- [TigerVNC Documentation](https://tigervnc.org/)
- [noVNC Documentation](https://novnc.com/)
