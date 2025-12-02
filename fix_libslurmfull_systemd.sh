#!/bin/bash

echo "=======================
# 2. src/api/Makefile ??
echo "2??  libslurmfull ?? Makefile ??..."
API_MAKEFILE="src/api/Makefil
echo "=========================================="
echo "🔧 libslurm==================="
echo "🔧 libslurmfull.so에 systemd 링크 추가"
echo "=========================================="
echo ""

cd /tmp/slurm-23.11.10

# 1. 현재 libslurmfull.so 확인
echo "1️⃣  현재 libslurmfull.so 링크 확인..."
if [ -f "/usr/local/slurm/lib/slurm/libslurmfull.so" ]; then
    ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep systemd || echo "❌ systemd 링크 없음"
fi
echo ""

# 2. src/api/Makefile 찾기
echo "2️⃣  libslurmfull 빌드 Makefile 확인..."
API_MAKEFILE="src/api/Makefile"
#!/bin/bash

echo "=======================
# 2. src/api/Makefile ??
echo "2??  libslurmfull ?? Makefile ??..."
API_MAKEFILE="src/api/Makefil
echo "=========================================="
echo "? libslurm==================="
echo "? libslurmfull.so? systemd ?? ??"
echo "=========================================="
echo ""

cd /tmp/slurm-23.11.10

# 1. ?? libslurmfull.so ??
echo "1??  ?? libslurmfull.so ?? ??..."
if [ -f "/usr/local/slurm/lib/slurm/libslurmfull.so" ]; then
    ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep systemd || echo "? systemd ?? ??"
fi
echo ""

# 2. src/api/Makefile ??
echo "2??  libslurmfull ?? Makefile ??..."
API_MAKEFILE="src/api/Makefile"

if [ ! -f "$API_MAKEFILE" ]; then
    echo "? $API_MAKEFILE? ?? ? ????"
    exit 1
fi

echo "? $API_MAKEFILE ??"
echo ""

# 3. ??
echo "3??  Makefile ??..."
cp "$API_MAKEFILE" "$API_MAKEFILE.backup"
echo "? ?? ??"

if [ ! -f "$API_MAKEFILE" ]; then
    echo "❌ $API_MAKEFILE을 찾을 수 없습니다"
    exit 1
fi

echo "✅ $API_MAKEFILE 찾음"
echo ""

# 3. 백업
echo "3️⃣  Makefile 백업..."
cp "$API_MAKEFILE" "$API_MAKEFILE.backup"
echo "✅ 백업 완료"
echo ""

# 4. libslurmfull 링커 플래그 확인
echo "4️⃣  현재 libslurmfull_la_LIBADD 확인..."
grep "libslurmfull_la_LIBADD" "$API_MAKEFILE" | head -3
echo ""

# 5. systemd 추가
echo "5️⃣  libslurmfull_la_LIBADD에 -lsystemd 추가..."

# libslurmfull_la_LIBADD에 -lsystemd 추가
sed -i '/^libslurmfull_la_LIBADD = /s/$/ -lsystemd/' "$API_MAKEFILE"

echo "✅ 수정 완료"
echo ""

# 6. 수정 확인
echo "6️⃣  수정된 libslurmfull_la_LIBADD:"
grep "libslurmfull_la_LIBADD" "$API_MAKEFILE" | head -3
echo ""

# 7. src/api만 재빌드
echo "7️⃣  src/api 재빌드..."
echo "--------------------------------------------------------------------------------"

cd src/api
make clean
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "❌ 빌드 실패"
    cd ../..
    exit 1
fi

echo ""
echo "✅ 빌드 완료"
cd ../..
echo ""

# 8. 재설치
echo "8️⃣  재설치..."
cd src/api
sudo make install
cd ../..
echo "✅ 설치 완료"
echo ""

# 9. libslurmfull.so 검증
echo "9️⃣  libslurmfull.so 검증..."
echo "--------------------------------------------------------------------------------"

if ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep -q systemd; then
    echo "✅ libslurmfull.so에 systemd 링크됨!"
    ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep systemd
else
    echo "❌ 여전히 systemd 링크 안 됨"
    echo ""
    echo "전체 ldd:"
    ldd /usr/local/slurm/lib/slurm/libslurmfull.so
fi

echo ""

# 10. slurmctld 재빌드 (libslurmfull이 변경되었으므로)
echo "🔟  slurmctld 재빌드..."
echo "--------------------------------------------------------------------------------"

cd src/slurmctld
make clean
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "❌ 빌드 실패"
    cd ../..
    exit 1
fi

sudo make install
cd ../..

echo "✅ slurmctld 재설치 완료"
echo ""

# 11. 최종 검증
echo "1️⃣1️⃣  최종 검증..."
echo "--------------------------------------------------------------------------------"

SLURMCTLD_BIN="/usr/local/slurm/sbin/slurmctld"

echo ""
echo "slurmctld ldd 확인:"
if ldd "$SLURMCTLD_BIN" | grep -q systemd; then
    echo "✅ slurmctld에 systemd 링크됨!"
    ldd "$SLURMCTLD_BIN" | grep systemd
else
    echo "⚠️  직접 링크는 없지만 libslurmfull을 통해 연결"
    echo ""
    echo "libslurmfull.so 링크:"
    ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep systemd
fi

echo ""

################################################################################
# 결론
################################################################################

if ldd /usr/local/slurm/lib/slurm/libslurmfull.so | grep -q systemd; then
    echo "=========================================="
    echo "✅ systemd 지원 빌드 성공!"
    echo "=========================================="
    echo ""
    echo "libslurmfull.so를 통해 systemd가 링크되었습니다."
    echo ""
    echo "다음 단계:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart slurmdbd"
    echo "  sudo systemctl restart slurmctld"
    echo "  sleep 15"
    echo "  sudo systemctl status slurmctld"
    echo ""
    echo "Type=notify가 이제 작동할 것입니다!"
else
    echo "=========================================="
    echo "❌ systemd 링크 여전히 실패"
    echo "=========================================="
    echo ""
    echo "최종 대안: Type=simple 사용"
    echo ""
    echo "Type=simple로 변경:"
    echo "  sudo sed -i 's/Type=notify/Type=simple/' /etc/systemd/system/slurmctld.service"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart slurmctld"
fi

echo ""
