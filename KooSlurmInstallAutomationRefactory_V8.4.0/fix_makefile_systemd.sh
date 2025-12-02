#!/bin/bash

echo "=========================================="
echo "🔧 Makefile에 -lsystemd 추가"
echo "=========================================="
echo ""

cd /tmp/slurm-23.11.10

# 1. 현재 LIBS 확인
echo "1️⃣  현재 LIBS:"
grep "^LIBS = " Makefile | head -1
echo ""

# 2. Makefile 백업
echo "2️⃣  Makefile 백업..."
cp Makefile Makefile.backup
echo "✅ Makefile.backup 생성"
echo ""

# 3. LIBS에 -lsystemd 추가
echo "3️⃣  LIBS에 -lsystemd 추가..."

# 모든 Makefile에서 LIBS 수정
find . -name Makefile -type f | while read makefile; do
    if grep -q "^LIBS = " "$makefile"; then
        # -lsystemd가 없으면 추가
        if ! grep "^LIBS = " "$makefile" | grep -q -- "-lsystemd"; then
            sed -i 's/^LIBS = \(.*\)/LIBS = \1 -lsystemd/' "$makefile"
            echo "   ✅ $makefile 수정"
        fi
    fi
done

echo ""
echo "✅ LIBS 수정 완료"
echo ""

# 4. 수정 확인
echo "4️⃣  수정된 LIBS:"
grep "^LIBS = " Makefile | head -1
echo ""

# 5. 재컴파일
echo "5️⃣  재컴파일..."
echo "--------------------------------------------------------------------------------"

# clean 필요 없음 (LIBS만 변경)
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "❌ 컴파일 실패"
    exit 1
fi

echo ""
echo "✅ 컴파일 완료"
echo ""

# 6. 설치
echo "6️⃣  설치..."
sudo make install

if [ $? -ne 0 ]; then
    echo "❌ 설치 실패"
    exit 1
fi

echo ""
echo "✅ 설치 완료"
echo ""

# 7. 검증
echo "7️⃣  systemd 링크 검증..."
echo "--------------------------------------------------------------------------------"

SLURMCTLD_BIN="/usr/local/slurm/sbin/slurmctld"

echo ""
echo "ldd 확인:"
if ldd "$SLURMCTLD_BIN" | grep -q systemd; then
    echo "   ✅ systemd 라이브러리 링크됨!"
    ldd "$SLURMCTLD_BIN" | grep systemd
else
    echo "   ❌ systemd 라이브러리 링크 안 됨"
fi

echo ""
echo "sd_notify 심볼 확인:"
if strings "$SLURMCTLD_BIN" | grep -q sd_notify; then
    echo "   ✅ sd_notify 심볼 있음!"
else
    echo "   ❌ sd_notify 심볼 없음"
fi

echo ""

if ldd "$SLURMCTLD_BIN" | grep -q systemd && strings "$SLURMCTLD_BIN" | grep -q sd_notify; then
    echo "=========================================="
    echo "✅ systemd 지원 재빌드 성공!"
    echo "=========================================="
    echo ""
    echo "이제 Type=notify가 작동합니다!"
    echo ""
    
    # 서비스 재시작
    echo "서비스 재시작:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart slurmdbd"
    echo "  sudo systemctl restart slurmctld"
else
    echo "=========================================="
    echo "❌ 여전히 systemd 링크 실패"
    echo "=========================================="
    echo ""
    echo "추가 디버깅 필요"
fi

echo ""
