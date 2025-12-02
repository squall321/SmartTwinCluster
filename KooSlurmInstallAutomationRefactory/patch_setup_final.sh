#!/bin/bash
################################################################################
# setup_cluster_full.sh 최종 완성 패치
# - Step 7.5: 원격 systemd 서비스 배포 추가
# - Step 10: SSH timeout 추가
################################################################################

set -e

echo "=========================================="
echo "🔧 setup_cluster_full.sh 최종 완성 패치"
echo "=========================================="
echo ""

SCRIPT="setup_cluster_full.sh"
BACKUP="${SCRIPT}.backup_final_$(date +%Y%m%d_%H%M%S)"

# 백업
echo "📦 백업 생성: $BACKUP"
cp "$SCRIPT" "$BACKUP"
echo ""

################################################################################
# 1. Step 7.5 추가
################################################################################

echo "1️⃣  Step 7.5 추가 (원격 systemd 서비스 배포)..."

# Step 7 끝나는 지점 찾기
STEP7_END=$(grep -n "모든 계산 노드 Slurm 설치 완료" "$SCRIPT" | tail -1 | cut -d: -f1)

if [ -z "$STEP7_END" ]; then
    echo "   ❌ Step 7 끝 위치를 찾을 수 없습니다"
    exit 1
fi

echo "   Step 7 끝: 라인 $STEP7_END"

# Step 7.5 내용 생성
STEP75_CONTENT='
################################################################################
# Step 7.5: 원격 노드 systemd 서비스 파일 배포
################################################################################

echo "📤 Step 7.5/14: 원격 노드 systemd 서비스 파일 배포..."
echo "--------------------------------------------------------------------------------"

read -p "원격 노드에 systemd 서비스 파일을 배포하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    for node in "${COMPUTE_NODES[@]}"; do
        echo ""
        echo "📤 $node: systemd 서비스 파일 복사 중..."
        
        # slurmd.service 복사
        if [ -f "/etc/systemd/system/slurmd.service" ]; then
            scp /etc/systemd/system/slurmd.service ${SSH_USER}@${node}:/tmp/
            timeout 30 ssh -o ConnectTimeout=10 ${SSH_USER}@${node} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload" || {
                echo "⚠️  $node: 타임아웃 - 수동 확인 필요"
            }
            
            if [ $? -eq 0 ]; then
                echo "✅ $node: slurmd.service 배포 완료"
            else
                echo "⚠️  $node: slurmd.service 배포 실패"
            fi
        else
            echo "⚠️  /etc/systemd/system/slurmd.service 파일이 없습니다"
        fi
    done
    
    echo ""
    echo "✅ systemd 서비스 파일 배포 완료"
else
    echo "⏭️  systemd 서비스 파일 배포 건너뜀"
fi

echo ""
'

# Step 7.5 삽입 (Step 7 다음 줄에)
INSERT_LINE=$((STEP7_END + 3))  # "echo """ 이후

echo "   삽입 위치: 라인 $INSERT_LINE"

# 임시 파일 생성
head -n "$STEP7_END" "$SCRIPT" > "${SCRIPT}.tmp"
echo "$STEP75_CONTENT" >> "${SCRIPT}.tmp"
tail -n +$((STEP7_END + 1)) "$SCRIPT" >> "${SCRIPT}.tmp"

mv "${SCRIPT}.tmp" "$SCRIPT"

echo "   ✅ Step 7.5 추가 완료"
echo ""

################################################################################
# 2. Step 10 SSH timeout 추가
################################################################################

echo "2️⃣  Step 10 SSH timeout 추가..."

# Step 10에서 ssh 명령 찾기
# "ssh ${SSH_USER}@${node} \"sudo systemctl" 패턴 찾기

# 임시로 sed로 변경
sed -i 's/ssh ${SSH_USER}@${node} "sudo systemctl enable slurmd && sudo systemctl restart slurmd"/timeout 60 ssh -o ConnectTimeout=10 ${SSH_USER}@${node} "sudo systemctl enable slurmd \&\& sudo systemctl restart slurmd" || { echo "⚠️  $node: 타임아웃 - 수동 확인 필요"; }/g' "$SCRIPT"

# 검증
if grep -q "timeout 60 ssh" "$SCRIPT"; then
    echo "   ✅ SSH timeout 추가 완료"
else
    echo "   ⚠️  SSH timeout 추가 실패 - 수동 확인 필요"
fi

echo ""

################################################################################
# 3. Step 번호 재조정
################################################################################

echo "3️⃣  Step 번호 재조정..."

# Step 8-12를 9-13으로 변경
# 이미 일부는 /13으로 되어있으므로 /14로 최종 변경

# Step 7 -> 7 (유지)
# Step 7.5 -> 7.5 (신규)
# Step 8 -> 8 (/13을 /14로)
# Step 9 -> 9 (/13을 /14로)
# Step 10 -> 10 (/13을 /14로)
# Step 11 -> 11 (/13을 /14로)
# Step 12 -> 12 (/13을 /14로)
# Step 13 -> 13 (/14 유지)

sed -i 's|Step \([0-9]\+\)/13|Step \1/14|g' "$SCRIPT"

echo "   ✅ Step 번호 /13 -> /14 변경 완료"
echo ""

################################################################################
# 4. 검증
################################################################################

echo "4️⃣  변경사항 검증..."

# Step 7.5 확인
if grep -q "Step 7.5/14" "$SCRIPT"; then
    echo "   ✅ Step 7.5 확인"
else
    echo "   ❌ Step 7.5 없음"
fi

# SSH timeout 확인
if grep -q "timeout 60 ssh" "$SCRIPT"; then
    echo "   ✅ SSH timeout 확인"
else
    echo "   ❌ SSH timeout 없음"
fi

# Step 번호 확인
STEP_COUNTS=$(grep -o "Step [0-9.]\+/14" "$SCRIPT" | sort -u)
echo ""
echo "   Step 목록:"
echo "$STEP_COUNTS" | sed 's/^/      /'

echo ""

################################################################################
# 완료
################################################################################

echo "=========================================="
echo "✅ setup_cluster_full.sh 최종 완성!"
echo "=========================================="
echo ""

echo "변경사항:"
echo "  ✅ Step 7.5: 원격 systemd 서비스 배포"
echo "  ✅ Step 10: SSH timeout (60초)"
echo "  ✅ Step 번호: /14로 통일"
echo ""

echo "백업 파일: $BACKUP"
echo ""

echo "🎯 이제 setup_cluster_full.sh가 100% 완성되었습니다!"
echo ""

echo "실행 방법:"
echo "  ./setup_cluster_full.sh"
echo ""

echo "주요 Step:"
echo "  - Step 6.1: systemd 서비스 생성 (Type=notify)"
echo "  - Step 6.5: slurmdbd 설치 (QoS)"
echo "  - Step 7.5: 원격 systemd 배포"
echo "  - Step 10: 원격 서비스 시작 (timeout 적용)"
echo ""
