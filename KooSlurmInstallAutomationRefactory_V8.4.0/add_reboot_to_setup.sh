#!/bin/bash

echo "================================================================================"
echo "🔧 setup_cluster_full.sh에 RebootProgram 설정 추가"
echo "================================================================================"
echo ""

SETUP_SCRIPT="/home/koopark/claude/KooSlurmInstallAutomationRefactory/setup_cluster_full.sh"

# 백업
cp "$SETUP_SCRIPT" "${SETUP_SCRIPT}.backup_reboot_$(date +%Y%m%d_%H%M%S)"
echo "✅ 백업 생성 완료"
echo ""

# RebootProgram 설정 스크립트 생성
cat > /home/koopark/claude/KooSlurmInstallAutomationRefactory/setup_reboot_program.sh <<'EOF'
#!/bin/bash

echo "================================================================================"
echo "🔄 Step: RebootProgram 설정"
echo "================================================================================"
echo ""

CURRENT_USER=$(whoami)
SCONTROL_PATH="/usr/local/slurm/bin/scontrol"
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

echo "📝 RebootProgram 스크립트 생성 중..."

# RebootProgram 스크립트 생성
sudo tee $REBOOT_SCRIPT > /dev/null <<'REBOOT_SCRIPT'
#!/bin/bash
NODE_NAME=$1
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p $(dirname $LOG_FILE)

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log_msg "=========================================="
log_msg "Reboot: $NODE_NAME"
log_msg "Executed as: $(whoami)"

# koopark 사용자로 SSH 실행
if su - koopark -c "ssh -o StrictHostKeyChecking=no -o BatchMode=yes koopark@${NODE_NAME} 'sudo /sbin/reboot'" >> $LOG_FILE 2>&1; then
    log_msg "✅ Reboot command sent successfully"
    exit 0
else
    log_msg "❌ SSH command failed"
    exit 1
fi
REBOOT_SCRIPT

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ RebootProgram 스크립트 생성: $REBOOT_SCRIPT"
echo ""

# slurm.conf에 RebootProgram 추가
echo "📝 slurm.conf 업데이트 중..."
if ! grep -q "^RebootProgram=" /usr/local/slurm/etc/slurm.conf; then
    echo "RebootProgram=$REBOOT_SCRIPT" | sudo tee -a /usr/local/slurm/etc/slurm.conf > /dev/null
    echo "✅ slurm.conf에 RebootProgram 추가"
else
    echo "⚠️  RebootProgram이 이미 설정되어 있습니다"
fi
echo ""

# sudoers 설정 (scontrol reboot 권한)
echo "🔒 sudoers 설정 중..."
sudo tee /etc/sudoers.d/slurm-dashboard-scontrol > /dev/null <<SUDOERS
# Slurm Dashboard - scontrol reboot permission
${CURRENT_USER} ALL=(ALL) NOPASSWD: ${SCONTROL_PATH} reboot *
${CURRENT_USER} ALL=(ALL) NOPASSWD: ${SCONTROL_PATH}
SUDOERS

sudo chmod 0440 /etc/sudoers.d/slurm-dashboard-scontrol
echo "✅ sudoers 설정 완료"
echo ""

# SSH 키 설정 안내
echo "================================================================================"
echo "🔑 SSH 키 설정 (노드 재부팅에 필요)"
echo "================================================================================"
echo ""
echo "각 노드에서 비밀번호 없이 재부팅하려면 SSH 키가 필요합니다:"
echo ""
echo "1. SSH 키 생성 (없으면):"
echo "   ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
echo ""
echo "2. 모든 노드에 SSH 키 복사:"
echo "   ssh-copy-id ${CURRENT_USER}@node001"
echo "   ssh-copy-id ${CURRENT_USER}@node002"
echo ""
echo "3. 각 노드에서 sudo 권한 설정 (비밀번호 없이 재부팅):"
echo "   ssh ${CURRENT_USER}@node001"
echo "   echo '${CURRENT_USER} ALL=(ALL) NOPASSWD: /sbin/reboot' | sudo tee /etc/sudoers.d/${CURRENT_USER}-reboot"
echo "   sudo chmod 0440 /etc/sudoers.d/${CURRENT_USER}-reboot"
echo "   exit"
echo ""
echo "   (node002도 동일하게 반복)"
echo ""
echo "4. 테스트:"
echo "   ssh ${CURRENT_USER}@node001 'sudo /sbin/reboot'"
echo ""
echo "자동화 스크립트가 필요하면 dashboard/backend_5010/setup_ssh_for_user.sh 참고"
echo ""
EOF

chmod +x /home/koopark/claude/KooSlurmInstallAutomationRefactory/setup_reboot_program.sh
echo "✅ setup_reboot_program.sh 생성 완료"
echo ""

# setup_cluster_full.sh에 단계 추가
echo "📝 setup_cluster_full.sh 수정 중..."

# Step 9 이후에 추가 (slurmctld 시작 이후)
# "다음 단계" 섹션 앞에 삽입
sed -i '/^echo "================================================================================"/i \
# Step: RebootProgram 설정\
if [ -f "./setup_reboot_program.sh" ]; then\
    echo ""\
    read -p "RebootProgram을 설정하시겠습니까? (웹 대시보드에서 노드 재부팅 기능) (Y/n): " -n 1 -r\
    echo ""\
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then\
        ./setup_reboot_program.sh\
    else\
        echo "⚠️  RebootProgram 설정을 건너뜁니다"\
        echo "   나중에 설정: ./setup_reboot_program.sh"\
    fi\
    echo ""\
fi\
' "$SETUP_SCRIPT"

echo "✅ setup_cluster_full.sh 수정 완료"
echo ""

echo "================================================================================"
echo "✅ 완료!"
echo "================================================================================"
echo ""
echo "📝 생성된 파일:"
echo "  - setup_reboot_program.sh"
echo ""
echo "📋 수정된 파일:"
echo "  - setup_cluster_full.sh"
echo ""
echo "🔍 확인:"
echo "  grep -A 3 'RebootProgram' setup_cluster_full.sh"
echo ""
echo "🧪 테스트:"
echo "  ./setup_reboot_program.sh"
echo ""
