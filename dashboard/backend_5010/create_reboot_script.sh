#!/bin/bash
# 노드 RebootProgram 스크립트 생성 스크립트

echo "================================================================================"
echo "🔧 RebootProgram 스크립트 생성"
echo "================================================================================"
echo ""

# 인자로 SSH_USER 받기
SSH_USER=${1:-root}
CURRENT_USER=$(whoami)

echo "설정 정보:"
echo "  - 현재 사용자: $CURRENT_USER"
echo "  - 노드 SSH 사용자: $SSH_USER"
echo "  - SSH 키: /home/$CURRENT_USER/.ssh/id_rsa"
echo ""

# scontrol 경로
SCONTROL_PATH=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
echo "  - scontrol 경로: $SCONTROL_PATH"
echo ""

read -p "계속하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 0
fi
echo ""

# 1. RebootProgram 스크립트 생성
echo "📝 Step 1/3: RebootProgram 스크립트 생성"
echo "--------------------------------------------------------------------------------"
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

sudo tee $REBOOT_SCRIPT > /dev/null <<EOF
#!/bin/bash
# Slurm Node Reboot Script
# 이 스크립트는 scontrol reboot 명령어로 호출됩니다
#
# 사용법: $REBOOT_SCRIPT <node_name>

NODE_NAME=\$1
SSH_USER="${SSH_USER}"
SUDO_USER="${CURRENT_USER}"

if [ -z "\$NODE_NAME" ]; then
    echo "Error: Node name is required"
    exit 1
fi

# 로그 파일
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p \$(dirname \$LOG_FILE)

# 로그 함수
log_msg() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> \$LOG_FILE
}

log_msg "=========================================="
log_msg "Reboot request for: \$NODE_NAME"
log_msg "SSH User: \$SSH_USER"
log_msg "Executed by: \$SUDO_USER"
log_msg "=========================================="

# sudo로 실행된 경우, 원래 사용자의 SSH 키 사용
if [ "\$SUDO_USER" != "" ] && [ "\$SUDO_USER" != "root" ]; then
    # sudo로 실행됨 - 원래 사용자의 SSH 키 사용
    SSH_KEY="/home/\$SUDO_USER/.ssh/id_rsa"
    log_msg "Using SSH key: \$SSH_KEY"
    
    # su를 사용하여 원래 사용자로 SSH 실행
    if su - \$SUDO_USER -c "ssh -i \$SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \${SSH_USER}@\${NODE_NAME} 'nohup sudo /sbin/reboot >/dev/null 2>&1 &'" 2>&1 >> \$LOG_FILE; then
        log_msg "✅ Reboot command sent successfully to \$NODE_NAME"
        exit 0
    else
        log_msg "❌ SSH command failed for \$NODE_NAME"
        exit 1
    fi
else
    # root로 직접 실행됨
    SSH_KEY="/root/.ssh/id_rsa"
    log_msg "Using root SSH key: \$SSH_KEY"
    
    if ssh -i \$SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \${SSH_USER}@\${NODE_NAME} "nohup sudo /sbin/reboot >/dev/null 2>&1 &" 2>&1 >> \$LOG_FILE; then
        log_msg "✅ Reboot command sent successfully to \$NODE_NAME"
        exit 0
    else
        log_msg "❌ SSH command failed for \$NODE_NAME"
        exit 1
    fi
fi
EOF

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ 스크립트 생성 완료: $REBOOT_SCRIPT"
echo ""

# 2. 스크립트 테스트
echo "🧪 Step 2/3: 스크립트 테스트"
echo "--------------------------------------------------------------------------------"

FIRST_NODE=$(sinfo -N -h -o "%N" | head -1)
echo "테스트 노드: $FIRST_NODE"
echo ""

read -p "테스트를 실행하시겠습니까? (실제 재부팅됨!) (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "테스트 실행 중..."
    echo "명령어: sudo $REBOOT_SCRIPT $FIRST_NODE"
    sudo $REBOOT_SCRIPT $FIRST_NODE
    RESULT=$?
    
    echo ""
    if [ $RESULT -eq 0 ]; then
        echo "✅ 스크립트 실행 성공 (Exit Code: 0)"
    else
        echo "❌ 스크립트 실행 실패 (Exit Code: $RESULT)"
    fi
    
    echo ""
    echo "로그 확인:"
    sudo tail -15 /var/log/slurm/node_reboot.log
    echo ""
else
    echo "⚠️  테스트를 건너뜁니다"
fi
echo ""

# 3. slurm.conf 업데이트
echo "📝 Step 3/3: slurm.conf 업데이트"
echo "--------------------------------------------------------------------------------"

# 백업
sudo cp /usr/local/slurm/etc/slurm.conf /usr/local/slurm/etc/slurm.conf.backup.$(date +%Y%m%d_%H%M%S)

# 기존 RebootProgram 제거하고 새로 추가
sudo sed -i '/^RebootProgram/d' /usr/local/slurm/etc/slurm.conf
echo "RebootProgram=$REBOOT_SCRIPT" | sudo tee -a /usr/local/slurm/etc/slurm.conf

echo "✅ slurm.conf 업데이트 완료"
echo ""
echo "현재 설정:"
grep "^RebootProgram" /usr/local/slurm/etc/slurm.conf
echo ""

# slurmctld 재시작
read -p "slurmctld를 재시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart slurmctld
    sleep 3
    
    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 재시작 성공"
    else
        echo "❌ slurmctld 재시작 실패"
        sudo journalctl -u slurmctld -n 20 --no-pager
    fi
fi
echo ""

echo "================================================================================"
echo "✅ 설정 완료!"
echo "================================================================================"
echo ""
echo "📋 생성된 파일:"
echo "  - RebootProgram: $REBOOT_SCRIPT"
echo "  - 로그 파일: /var/log/slurm/node_reboot.log"
echo ""
echo "🔑 SSH 설정:"
echo "  - 현재 사용자: $CURRENT_USER"
echo "  - SSH 키: /home/$CURRENT_USER/.ssh/id_rsa"
echo "  - 노드 접속: ssh ${SSH_USER}@<node_name>"
echo ""
echo "🧪 테스트 방법:"
echo ""
echo "  1. SSH 연결 테스트:"
echo "     ssh ${SSH_USER}@${FIRST_NODE} 'hostname'"
echo ""
echo "  2. RebootProgram 직접 실행:"
echo "     sudo $REBOOT_SCRIPT ${FIRST_NODE}"
echo ""
echo "  3. scontrol 명령어:"
echo "     $SCONTROL_PATH reboot ${FIRST_NODE} reason='test'"
echo ""
echo "  4. sudo로 scontrol:"
echo "     sudo $SCONTROL_PATH reboot ${FIRST_NODE} reason='test'"
echo ""
echo "  5. 웹 대시보드에서 Reboot 버튼 클릭"
echo ""
echo "📄 로그 확인:"
echo "  sudo tail -f /var/log/slurm/node_reboot.log"
echo ""
