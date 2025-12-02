#!/bin/bash
# Slurm Node Reboot Script
# 이 스크립트는 scontrol reboot 명령어로 호출됩니다

NODE_NAME=$1
SSH_USER="koopark"
SSH_KEY="/home/koopark/.ssh/id_rsa"

if [ -z "$NODE_NAME" ]; then
    echo "Error: Node name is required"
    exit 1
fi

# 로그 파일
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p $(dirname $LOG_FILE)

# 로그 함수
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log_msg "=========================================="
log_msg "Reboot request for: $NODE_NAME"
log_msg "SSH User: $SSH_USER"
log_msg "SSH Key: $SSH_KEY"
log_msg "Executed as: $(whoami)"
log_msg "=========================================="

# su를 사용하여 koopark 사용자로 SSH 실행
if su - koopark -c "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ${SSH_USER}@${NODE_NAME} 'nohup sudo /sbin/reboot >/dev/null 2>&1 &'" 2>&1 >> $LOG_FILE; then
    log_msg "✅ Reboot command sent successfully to $NODE_NAME"
    exit 0
else
    log_msg "❌ SSH command failed for $NODE_NAME"
    exit 1
fi
