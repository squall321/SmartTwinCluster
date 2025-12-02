#!/bin/bash

echo "=========================================="
echo "🔍 Type=notify 작동 실패 원인 분석"
echo "=========================================="
echo ""

# 1. Slurm이 systemd 지원으로 빌드되었는지 확인
echo "1️⃣  Slurm systemd 지원 확인:"
echo "----------------------------------------"

SLURMCTLD_BIN="/usr/local/slurm/sbin/slurmctld"

if [ -f "$SLURMCTLD_BIN" ]; then
    echo "slurmctld 경로: $SLURMCTLD_BIN"
    
    # ldd로 systemd 라이브러리 링크 확인
    echo ""
    echo "systemd 라이브러리 링크:"
    ldd "$SLURMCTLD_BIN" | grep systemd || echo "❌ systemd 라이브러리 링크 없음!"
    
    # strings로 sd_notify 심볼 확인
    echo ""
    echo "sd_notify 심볼 확인:"
    strings "$SLURMCTLD_BIN" | grep sd_notify || echo "❌ sd_notify 심볼 없음!"
    
    # nm으로 심볼 테이블 확인
    echo ""
    echo "systemd 관련 심볼:"
    nm -D "$SLURMCTLD_BIN" 2>/dev/null | grep -i systemd || echo "❌ systemd 심볼 없음"
else
    echo "❌ slurmctld 바이너리를 찾을 수 없습니다"
fi

echo ""

# 2. 빌드 시 configure 옵션 확인
echo "2️⃣  Slurm 빌드 옵션 확인:"
echo "----------------------------------------"

if [ -f "/tmp/slurm-23.11.10/config.log" ]; then
    echo "config.log에서 systemd 관련 확인:"
    grep -i "systemd" /tmp/slurm-23.11.10/config.log | grep -v "^#" | head -10
elif [ -f "/tmp/slurm-23.11.10/config.h" ]; then
    echo "config.h에서 systemd 관련 확인:"
    grep -i "HAVE_SYSTEMD\|SYSTEMD" /tmp/slurm-23.11.10/config.h
else
    echo "⚠️  빌드 로그를 찾을 수 없습니다"
fi

echo ""

# 3. systemd 개발 라이브러리 설치 확인
echo "3️⃣  systemd 개발 라이브러리 확인:"
echo "----------------------------------------"

if dpkg -l | grep -q "libsystemd-dev"; then
    echo "✅ libsystemd-dev 설치됨"
    dpkg -l | grep libsystemd
else
    echo "❌ libsystemd-dev 설치 안 됨!"
    echo ""
    echo "설치 명령:"
    echo "  sudo apt-get install -y libsystemd-dev"
fi

echo ""

# 4. pkg-config로 systemd 라이브러리 확인
echo "4️⃣  pkg-config systemd 확인:"
echo "----------------------------------------"

if pkg-config --exists libsystemd; then
    echo "✅ libsystemd pkg-config 설정 있음"
    echo ""
    echo "버전:"
    pkg-config --modversion libsystemd
    echo ""
    echo "CFLAGS:"
    pkg-config --cflags libsystemd
    echo ""
    echo "LIBS:"
    pkg-config --libs libsystemd
else
    echo "❌ libsystemd pkg-config 설정 없음"
fi

echo ""

# 5. 실행 시 sd_notify 호출 확인 (strace)
echo "5️⃣  런타임 sd_notify 호출 확인 (strace):"
echo "----------------------------------------"

echo "임시로 slurmctld를 strace로 실행하여 sd_notify 호출 확인..."
echo "이 작업은 시간이 걸릴 수 있습니다 (Ctrl+C로 중단)"
echo ""

read -p "strace 테스트를 실행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 기존 slurmctld 종료
    sudo systemctl stop slurmctld
    sudo pkill -9 slurmctld
    
    echo ""
    echo "strace 실행 중 (10초)..."
    timeout 10 sudo strace -e trace=sendto -o /tmp/slurmctld_strace.log /usr/local/slurm/sbin/slurmctld -D 2>&1 &
    STRACE_PID=$!
    
    sleep 10
    sudo kill -9 $STRACE_PID 2>/dev/null || true
    
    echo ""
    echo "sd_notify 관련 sendto 호출:"
    grep -i "sd_notify\|@/org/freedesktop/systemd1" /tmp/slurmctld_strace.log || echo "❌ sd_notify 호출 없음!"
    
    echo ""
    echo "전체 strace 로그: /tmp/slurmctld_strace.log"
else
    echo "⏭️  strace 테스트 건너뜀"
fi

echo ""

# 6. NOTIFY_SOCKET 환경변수 확인
echo "6️⃣  NOTIFY_SOCKET 환경변수 확인:"
echo "----------------------------------------"

sudo systemctl start slurmctld 2>/dev/null || true
sleep 3

SLURMCTLD_PID=$(pgrep -x slurmctld | head -1)

if [ -n "$SLURMCTLD_PID" ]; then
    echo "slurmctld PID: $SLURMCTLD_PID"
    echo ""
    echo "환경변수:"
    sudo cat /proc/$SLURMCTLD_PID/environ | tr '\0' '\n' | grep NOTIFY_SOCKET || echo "❌ NOTIFY_SOCKET 없음!"
else
    echo "⚠️  slurmctld가 실행되지 않음"
fi

echo ""

# 7. systemd 버전 확인
echo "7️⃣  systemd 버전 확인:"
echo "----------------------------------------"
systemctl --version | head -2

echo ""

################################################################################
# 결론 및 해결책
################################################################################

echo "=========================================="
echo "📋 진단 결과 및 해결책"
echo "=========================================="
echo ""

# 진단 결과 저장
HAS_SYSTEMD_LIB=false
HAS_SYSTEMD_DEV=false
HAS_SD_NOTIFY=false

if ldd "$SLURMCTLD_BIN" 2>/dev/null | grep -q systemd; then
    HAS_SYSTEMD_LIB=true
fi

if dpkg -l | grep -q "libsystemd-dev"; then
    HAS_SYSTEMD_DEV=true
fi

if strings "$SLURMCTLD_BIN" 2>/dev/null | grep -q sd_notify; then
    HAS_SD_NOTIFY=true
fi

echo "진단 요약:"
echo "  systemd 라이브러리 링크: $HAS_SYSTEMD_LIB"
echo "  libsystemd-dev 설치: $HAS_SYSTEMD_DEV"
echo "  sd_notify 심볼: $HAS_SD_NOTIFY"
echo ""

if [ "$HAS_SYSTEMD_LIB" = false ] || [ "$HAS_SD_NOTIFY" = false ]; then
    echo "❌ 문제: Slurm이 systemd 지원 없이 빌드됨"
    echo ""
    echo "🔧 해결 방법:"
    echo ""
    echo "1. libsystemd-dev 설치:"
    echo "   sudo apt-get update"
    echo "   sudo apt-get install -y libsystemd-dev"
    echo ""
    echo "2. Slurm 재빌드 (systemd 지원 포함):"
    echo "   cd /tmp/slurm-23.11.10"
    echo "   ./configure --prefix=/usr/local/slurm --with-systemd"
    echo "   make clean"
    echo "   make -j\$(nproc)"
    echo "   sudo make install"
    echo ""
    echo "3. 서비스 재시작:"
    echo "   sudo systemctl daemon-reload"
    echo "   sudo systemctl restart slurmctld"
    echo ""
    echo "또는 빠른 스크립트:"
    echo "   ./rebuild_slurm_with_systemd.sh"
    echo ""
else
    echo "✅ Slurm이 systemd 지원으로 빌드됨"
    echo ""
    echo "다른 가능한 원인:"
    echo "  - systemd 소켓 통신 문제"
    echo "  - SELinux/AppArmor 차단"
    echo "  - 권한 문제"
    echo ""
    echo "🔧 추가 디버깅:"
    echo "   journalctl -u slurmctld -f"
    echo "   sudo SYSTEMD_LOG_LEVEL=debug systemctl start slurmctld"
fi

echo ""
