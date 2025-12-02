#!/bin/bash

echo "=========================================="
echo "🔧 전역 LIBS 및 재configure"
echo "=========================================="
echo ""

cd /tmp/slurm-23.11.10

# 1. 완전히 clean
echo "1️⃣  Clean build..."
make distclean 2>/dev/null || make clean 2>/dev/null || true
echo "✅ Clean 완료"
echo ""

# 2. 환경변수 설정
echo "2️⃣  환경변수 설정..."
export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export SYSTEMD_CFLAGS="$(pkg-config --cflags libsystemd)"
export SYSTEMD_LIBS="$(pkg-config --libs libsystemd)"

echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "SYSTEMD_LIBS: $SYSTEMD_LIBS"
echo ""

# 3. 명시적인 LIBS와 함께 configure
echo "3️⃣  Configure (LIBS 명시)..."
echo "--------------------------------------------------------------------------------"

./configure \
    --prefix=/usr/local/slurm \
    --sysconfdir=/usr/local/slurm/etc \
    --enable-pam \
    --with-pmix \
    --with-hwloc=/usr \
    --without-rpath \
    LIBS="-lsystemd -lpthread -lm -lresolv"

if [ $? -ne 0 ]; then
    echo "❌ Configure 실패"
    exit 1
fi

echo ""
echo "✅ Configure 완료"
echo ""

# 4. config.h 검증
echo "4️⃣  config.h 검증..."
if grep -q "#define HAVE_SYSTEMD 1" config.h; then
    echo "✅ HAVE_SYSTEMD 정의됨"
else
    echo "❌ HAVE_SYSTEMD 정의 안 됨"
    exit 1
fi
echo ""

# 5. Makefile LIBS 검증
echo "5️⃣  Makefile LIBS 검증..."
MAIN_LIBS=$(grep "^LIBS = " Makefile | head -1)
echo "Main Makefile LIBS: $MAIN_LIBS"

if echo "$MAIN_LIBS" | grep -q "systemd"; then
    echo "✅ LIBS에 systemd 포함됨"
else
    echo "❌ LIBS에 systemd 없음"
    echo ""
    echo "수동으로 추가 중..."
    
    # 모든 Makefile 수정
    find . -name Makefile -type f -exec sed -i 's/^LIBS = \(.*\)$/LIBS = \1 -lsystemd/' {} \;
    
    echo "✅ 모든 Makefile에 -lsystemd 추가"
fi
echo ""

# 6. slurmctld Makefile 특별 확인
echo "6️⃣  slurmctld Makefile 확인..."
if [ -f "src/slurmctld/Makefile" ]; then
    SLURMCTLD_LIBS=$(grep "^LIBS = " src/slurmctld/Makefile | head -1)
    echo "slurmctld LIBS: $SLURMCTLD_LIBS"
    
    if ! echo "$SLURMCTLD_LIBS" | grep -q "systemd"; then
        echo "⚠️  slurmctld Makefile에 systemd 없음, 추가 중..."
        sed -i 's/^LIBS = \(.*\)$/LIBS = \1 -lsystemd/' src/slurmctld/Makefile
        echo "✅ 추가 완료"
    fi
fi
echo ""

# 7. 컴파일
echo "7️⃣  컴파일 (약 10-15분)..."
echo "--------------------------------------------------------------------------------"

make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "❌ 컴파일 실패"
    exit 1
fi

echo ""
echo "✅ 컴파일 완료"
echo ""

# 8. 설치
echo "8️⃣  설치..."
sudo make install

if [ $? -ne 0 ]; then
    echo "❌ 설치 실패"
    exit 1
fi

echo ""
echo "✅ 설치 완료"
echo ""

# 9. 최종 검증
echo "9️⃣  최종 검증..."
echo "--------------------------------------------------------------------------------"

SLURMCTLD_BIN="/usr/local/slurm/sbin/slurmctld"

echo ""
echo "ldd libsystemd 확인:"
if ldd "$SLURMCTLD_BIN" | grep -q libsystemd; then
    echo "✅ libsystemd 링크됨!"
    ldd "$SLURMCTLD_BIN" | grep systemd
else
    echo "❌ libsystemd 링크 안 됨"
    echo ""
    echo "전체 ldd 출력:"
    ldd "$SLURMCTLD_BIN"
fi

echo ""
echo "sd_notify 심볼 확인:"
if nm -D "$SLURMCTLD_BIN" 2>/dev/null | grep -q sd_notify; then
    echo "✅ sd_notify 심볼 있음!"
    nm -D "$SLURMCTLD_BIN" | grep sd_notify
elif strings "$SLURMCTLD_BIN" | grep -q sd_notify; then
    echo "✅ sd_notify 문자열 있음!"
else
    echo "❌ sd_notify 없음"
fi

echo ""

# 10. 빌드 로그 확인
echo "🔟  빌드 로그 분석..."
echo "slurmctld 링커 명령어 확인:"

# 마지막 빌드에서 slurmctld 링크 명령어 찾기
if [ -f "src/slurmctld/.libs/slurmctld" ]; then
    echo "✅ slurmctld 바이너리 생성됨"
    
    # libtool 명령어 확인
    if [ -f "src/slurmctld/.libs/slurmctld.cmd" ]; then
        cat src/slurmctld/.libs/slurmctld.cmd
    fi
else
    echo "⚠️  slurmctld 바이너리 확인 필요"
fi

echo ""

################################################################################
# 결론
################################################################################

if ldd "$SLURMCTLD_BIN" | grep -q libsystemd; then
    echo "=========================================="
    echo "✅ systemd 지원 빌드 성공!"
    echo "=========================================="
    echo ""
    echo "다음 단계:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart slurmdbd"
    echo "  sudo systemctl restart slurmctld"
    echo "  sudo systemctl status slurmctld"
else
    echo "=========================================="
    echo "❌ systemd 링크 여전히 실패"
    echo "=========================================="
    echo ""
    echo "대안: Slurm 소스 수정 또는 Type=simple 사용"
fi

echo ""
