#!/bin/bash

echo "=========================================="
echo "🔍 systemd 링크 실패 원인 분석"
echo "=========================================="
echo ""

cd /tmp/slurm-23.11.10

# 1. config.h 확인
echo "1️⃣  config.h HAVE_SYSTEMD 확인:"
if grep -q "HAVE_SYSTEMD" config.h 2>/dev/null; then
    grep "HAVE_SYSTEMD" config.h
else
    echo "❌ HAVE_SYSTEMD 정의 없음!"
fi
echo ""

# 2. config.log의 systemd 체크
echo "2️⃣  config.log systemd 체크:"
grep -A15 "checking for systemd" config.log | head -20
echo ""

# 3. pkg-config로 systemd 확인
echo "3️⃣  pkg-config systemd 확인:"
if pkg-config --exists libsystemd; then
    echo "✅ pkg-config가 libsystemd를 찾음"
    echo "   Cflags: $(pkg-config --cflags libsystemd)"
    echo "   Libs: $(pkg-config --libs libsystemd)"
    
    # 실제 라이브러리 파일 확인
    echo ""
    echo "   라이브러리 파일:"
    pkg-config --libs libsystemd | xargs -n1 | while read lib; do
        if [[ "$lib" == -l* ]]; then
            libname="${lib#-l}"
            ldconfig -p | grep "lib${libname}" || echo "     ⚠️  lib${libname} not found in ldconfig"
        fi
    done
else
    echo "❌ pkg-config가 libsystemd를 찾지 못함!"
fi
echo ""

# 4. 수동으로 systemd 헤더 확인
echo "4️⃣  systemd 헤더 파일 확인:"
if [ -f "/usr/include/systemd/sd-daemon.h" ]; then
    echo "✅ /usr/include/systemd/sd-daemon.h 존재"
else
    echo "❌ /usr/include/systemd/sd-daemon.h 없음!"
fi
echo ""

# 5. 수동으로 systemd 라이브러리 확인
echo "5️⃣  systemd 라이브러리 파일 확인:"
if ldconfig -p | grep -q libsystemd; then
    echo "✅ libsystemd 라이브러리 찾음:"
    ldconfig -p | grep libsystemd
else
    echo "❌ libsystemd 라이브러리 없음!"
fi
echo ""

# 6. Makefile에서 LIBS 확인
echo "6️⃣  Makefile LIBS 확인:"
if [ -f "Makefile" ]; then
    echo "LIBS 변수:"
    grep "^LIBS = " Makefile | head -5
else
    echo "❌ Makefile 없음"
fi
echo ""

echo "=========================================="
echo "📋 진단 결과"
echo "=========================================="
echo ""

# config.h에 HAVE_SYSTEMD가 있는지 확인
HAS_SYSTEMD_DEFINE=false
if grep -q "#define HAVE_SYSTEMD 1" config.h 2>/dev/null; then
    HAS_SYSTEMD_DEFINE=true
fi

echo "HAVE_SYSTEMD 정의: $HAS_SYSTEMD_DEFINE"

if [ "$HAS_SYSTEMD_DEFINE" = false ]; then
    echo ""
    echo "❌ 문제: configure가 systemd를 감지하지 못했습니다"
    echo ""
    echo "🔧 해결 방법:"
    echo ""
    echo "1. 명시적으로 CPPFLAGS와 LIBS 지정:"
    echo "   ./configure \\"
    echo "     --prefix=/usr/local/slurm \\"
    echo "     --sysconfdir=/usr/local/slurm/etc \\"
    echo "     --enable-pam \\"
    echo "     --with-pmix \\"
    echo "     --with-hwloc=/usr \\"
    echo "     --without-rpath \\"
    echo "     CPPFLAGS=\"-I/usr/include\" \\"
    echo "     LIBS=\"-lsystemd\""
    echo ""
    echo "2. 또는 PKG_CONFIG_PATH 설정:"
    echo "   export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig"
    echo "   ./configure ..."
    echo ""
fi

echo ""
