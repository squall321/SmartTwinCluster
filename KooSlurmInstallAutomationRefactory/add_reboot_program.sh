#!/bin/bash

echo "========================================"
echo "🔧 slurm.conf에 RebootProgram 추가"
echo "========================================"
echo ""

SLURM_CONF="/usr/local/slurm/etc/slurm.conf"
REBOOT_PROGRAM="${1:-/sbin/reboot}"

# 1. 파일 존재 확인
if [ ! -f "$SLURM_CONF" ]; then
    echo "❌ 오류: $SLURM_CONF 파일을 찾을 수 없습니다"
    exit 1
fi

# 2. 이미 RebootProgram이 있는지 확인
echo "1️⃣ 기존 설정 확인..."
if grep -q "^RebootProgram" "$SLURM_CONF"; then
    EXISTING=$(grep "^RebootProgram" "$SLURM_CONF")
    echo "   ⚠️  이미 RebootProgram이 설정되어 있습니다:"
    echo "      $EXISTING"
    echo ""
    read -p "덮어쓰시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   취소되었습니다."
        exit 0
    fi
    # 기존 설정 제거
    sudo sed -i.bak "/^RebootProgram/d" "$SLURM_CONF"
fi

# 3. 백업 생성
echo ""
echo "2️⃣ 백업 생성..."
BACKUP_FILE="${SLURM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
sudo cp "$SLURM_CONF" "$BACKUP_FILE"
echo "   ✅ 백업 완료: $BACKUP_FILE"

# 4. RebootProgram 추가
echo ""
echo "3️⃣ RebootProgram 추가..."
echo "   추가할 내용: RebootProgram=$REBOOT_PROGRAM"

# Authentication 섹션 찾기
if grep -q "^CryptoType" "$SLURM_CONF"; then
    # CryptoType 다음 줄에 추가
    sudo sed -i "/^CryptoType/a \\\n# Reboot Program\nRebootProgram=$REBOOT_PROGRAM" "$SLURM_CONF"
    echo "   ✅ CryptoType 다음에 추가됨"
elif grep -q "^AuthType" "$SLURM_CONF"; then
    # AuthType 다음 줄에 추가
    sudo sed -i "/^AuthType/a \\\n# Reboot Program\nRebootProgram=$REBOOT_PROGRAM" "$SLURM_CONF"
    echo "   ✅ AuthType 다음에 추가됨"
else
    # 파일 맨 앞에 추가
    echo -e "# Reboot Program\nRebootProgram=$REBOOT_PROGRAM\n" | sudo tee -a "$SLURM_CONF.tmp" > /dev/null
    sudo cat "$SLURM_CONF" | sudo tee -a "$SLURM_CONF.tmp" > /dev/null
    sudo mv "$SLURM_CONF.tmp" "$SLURM_CONF"
    echo "   ✅ 파일 시작 부분에 추가됨"
fi

# 5. 결과 확인
echo ""
echo "4️⃣ 추가 결과 확인..."
if grep -q "^RebootProgram=$REBOOT_PROGRAM" "$SLURM_CONF"; then
    echo "   ✅ 성공적으로 추가됨!"
    echo ""
    echo "   추가된 내용:"
    grep -A 2 -B 2 "^RebootProgram" "$SLURM_CONF" | sed 's/^/      /'
else
    echo "   ❌ 추가 실패"
    echo "   백업에서 복원: sudo cp $BACKUP_FILE $SLURM_CONF"
    exit 1
fi

# 6. 설정 검증
echo ""
echo "5️⃣ Slurm 설정 검증..."
if command -v slurmctld &> /dev/null; then
    sudo slurmctld -C 2>&1 | head -5
    if [ $? -eq 0 ]; then
        echo "   ✅ 설정 파일이 올바릅니다"
    else
        echo "   ⚠️  설정 검증 중 경고 발생 (확인 필요)"
    fi
else
    echo "   ⚠️  slurmctld 명령어 없음 (수동 검증 필요)"
fi

# 7. 계산 노드에도 복사
echo ""
echo "6️⃣ 계산 노드에 복사..."
echo "   다음 명령어로 모든 계산 노드에 복사하세요:"
echo ""
echo "   # node001에 복사"
echo "   scp $SLURM_CONF node001:$SLURM_CONF"
echo ""
echo "   # node002에 복사"
echo "   scp $SLURM_CONF node002:$SLURM_CONF"
echo ""
echo "   # 또는 모든 노드에 한 번에:"
echo "   for node in node001 node002; do"
echo "     scp $SLURM_CONF \$node:$SLURM_CONF"
echo "   done"

# 8. Slurm 재시작 안내
echo ""
echo "========================================"
echo "✅ 설정 완료!"
echo "========================================"
echo ""
echo "🔄 다음 단계: Slurm 서비스 재시작"
echo ""
echo "   # 컨트롤러에서:"
echo "   sudo systemctl restart slurmctld"
echo ""
echo "   # 각 계산 노드에서:"
echo "   ssh node001 'sudo systemctl restart slurmd'"
echo "   ssh node002 'sudo systemctl restart slurmd'"
echo ""
echo "🧪 테스트:"
echo "   scontrol show config | grep RebootProgram"
echo "   scontrol reboot node001 reason=\"test\""
echo ""
echo "📚 백업 파일: $BACKUP_FILE"
echo "   복원: sudo cp $BACKUP_FILE $SLURM_CONF"
echo ""
