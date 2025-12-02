#!/bin/bash
set -e

# 환경 변수 기본값 설정
VNC_RESOLUTION=${VNC_RESOLUTION:-1280x720}
VNC_DEPTH=${VNC_DEPTH:-24}
VNC_PORT=${VNC_PORT:-5901}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
DISPLAY=${DISPLAY:-:1}

echo "==================================="
echo "Starting GEdit with VNC"
echo "==================================="
echo "Display: $DISPLAY"
echo "Resolution: $VNC_RESOLUTION"
echo "VNC Port: $VNC_PORT"
echo "WebSocket Port: $WEBSOCKIFY_PORT"
echo "==================================="

# VNC 서버 정리 (기존 프로세스가 있을 경우)
vncserver -kill $DISPLAY 2>/dev/null || true

# X11 lock 파일 정리
rm -f /tmp/.X11-unix/X${DISPLAY#:} /tmp/.X${DISPLAY#:}-lock 2>/dev/null || true

# VNC 디렉토리 및 xstartup 파일 생성 (앱만 실행)
mkdir -p /root/.vnc
cat > /root/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# X 리소스 로드 (존재하는 경우)
[ -f $HOME/.Xresources ] && xrdb $HOME/.Xresources

# 배경색 설정
xsetroot -solid grey &

# DBus 세션 시작 (gedit에 필요)
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

# 간단한 window manager 시작 (창 관리를 위해)
# xfwm4는 XFCE의 경량 window manager
xfwm4 &

# 1초 대기 (window manager 초기화)
sleep 1

# GEdit 실행 (로그 파일로 출력)
gedit > /tmp/gedit.log 2>&1 &

# 위의 프로세스들이 종료되지 않도록 무한 대기
while true; do
    sleep 3600
done
EOF
chmod +x /root/.vnc/xstartup

# VNC 서버 시작
echo "Starting VNC server..."
vncserver $DISPLAY \
    -geometry $VNC_RESOLUTION \
    -depth $VNC_DEPTH \
    -localhost no \
    -SecurityTypes None \
    -AlwaysShared \
    -AcceptSetDesktopSize \
    -desktop "GEdit" \
    --I-KNOW-THIS-IS-INSECURE \
    2>&1 | tee /tmp/vncserver.log &

# VNC 서버 시작 대기
echo "Waiting for VNC server to start..."
sleep 5
if [ -f /root/.vnc/*:${DISPLAY#:}.pid ]; then
    echo "VNC server started successfully (PID file found)"
else
    echo "WARNING: VNC PID file not found, but continuing..."
fi

# XFCE 시작 대기
sleep 3

# WebSocket 프록시 + HTTP 서버 시작 (noVNC용)
# websockify --web 옵션으로 HTTP 서버 기능 포함
echo "Starting websockify with HTTP server on port ${WEBSOCKIFY_PORT}..."
websockify --web /opt/novnc ${WEBSOCKIFY_PORT} localhost:${VNC_PORT} &

echo "==================================="
echo "✅ GEdit is ready!"
echo "VNC: localhost:${VNC_PORT}"
echo "WebSocket: ws://localhost:${WEBSOCKIFY_PORT}"
echo "noVNC URL: http://localhost:${WEBSOCKIFY_PORT}/vnc.html"
echo "==================================="

# 로그 출력 (foreground로 실행하여 스크립트가 종료되지 않도록)
# tail -f는 무한히 실행되므로 이것이 스크립트를 살려둠
tail -f /root/.vnc/*.log
