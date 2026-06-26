#!/bin/bash
# 커스텀 RebootProgram 스크립트 설정 스크립트

echo "================================================================================"
echo "🔧 커스텀 RebootProgram 스크립트 생성"
echo "================================================================================"
echo ""
echo "이 스크립트는 SSH를 통해 원격 노드를 재부팅하는 커스텀 스크립트를 생성합니다"
echo ""

# 1. 스크립트 생성
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

echo "📝 Step 1/4: 커스텀 RebootProgram 스크립트 생성"
echo "--------------------------------------------------------------------------------"
echo "스크립트 경로: $REBOOT_SCRIPT"
echo ""

sudo tee $REBOOT_SCRIPT > /dev/null <<'EOF'
#!/bin/bash
# Slurm Node Reboot Script
# 이 스크립트는 scontrol reboot 명령어로 호출됩니다

# 사용법: slurm_reboot_node.sh <node_name>
NODE_NAME=$1

if [ -z "$NODE_NAME" ]; then
    echo "Error: Node name is required"
    echo "Usage: $0 <node_name>"
    exit 1
fi

# 로그 파일
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p $(dirname $LOG_FILE)

# 로그 기록
echo "$(date '+%Y-%m-%d %H:%M:%S') - Reboot request for node: $NODE_NAME" >> $LOG_FILE

# 방법 1: SSH를 통한 재부팅 (권장)
# SSH 키 기반 인증이 설정되어 있어야 함
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $NODE_NAME "sudo /sbin/reboot" 2>&1 >> $LOG_FILE; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Successfully sent reboot command to $NODE_NAME via SSH" >> $LOG_FILE
    exit 0
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SSH reboot failed for $NODE_NAME, trying alternative methods" >> $LOG_FILE
fi

# 방법 2: 로컬 재부팅 (컨트롤러와 노드가 같은 경우)
if [ "$NODE_NAME" == "$(hostname)" ] || [ "$NODE_NAME" == "$(hostname -s)" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Rebooting local node" >> $LOG_FILE
    /sbin/reboot
    exit 0
fi

# 방법 3: IPMI (BMC가 있는 경우)
# ipmitool -H ${NODE_NAME}-ipmi -U admin -P password power cycle

echo "$(date '+%Y-%m-%d %H:%M:%S') - All reboot methods failed for $NODE_NAME" >> $LOG_FILE
exit 1
EOF

echo "✅ 스크립트 생성 완료"
echo ""

# 2. 권한 설정
echo "🔒 Step 2/4: 권한 설정"
echo "--------------------------------------------------------------------------------"
sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ 권한 설정 완료"
ls -l $REBOOT_SCRIPT
echo ""

# 3. slurm.conf 업데이트
echo "📝 Step 3/4: slurm.conf 업데이트"
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

# 4. slurmctld 재시작
echo "🔄 Step 4/4: slurmctld 재시작"
echo "--------------------------------------------------------------------------------"

read -p "slurmctld를 재시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo systemctl restart slurmctld
    sleep 3
    
    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 재시작 성공"
        
        # 설정 확인
        echo ""
        echo "RebootProgram 설정 확인:"
        scontrol show config | grep -i reboot
    else
        echo "❌ slurmctld 재시작 실패"
        echo ""
        echo "로그 확인:"
        sudo journalctl -u slurmctld -n 20 --no-pager
    fi
else
    echo "⚠️  재시작을 건너뜁니다"
    echo "   수동으로 재시작: sudo systemctl restart slurmctld"
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
echo "🔧 SSH 키 설정 (노드 재부팅을 위해 필요):"
echo "  1. 컨트롤러에서 SSH 키 생성 (이미 있으면 생략):"
echo "     ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
echo ""
echo "  2. 각 노드에 SSH 키 복사:"
echo "     ssh-copy-id node001"
echo "     ssh-copy-id node002"
echo ""
echo "  3. SSH 연결 테스트:"
echo "     ssh node001 'echo SSH OK'"
echo ""
echo "🧪 테스트:"
echo "  1. 커맨드라인에서:"
echo "     sudo $REBOOT_SCRIPT node001"
echo ""
echo "  2. scontrol 명령어로:"
echo "     sudo scontrol reboot node001 reason='test'"
echo ""
echo "  3. 웹 대시보드에서 Reboot 버튼 클릭"
echo ""
echo "📄 로그 확인:"
echo "  sudo tail -f /var/log/slurm/node_reboot.log"
echo ""
