#!/bin/bash
# SSH 키 기반 RebootProgram 설정 스크립트(문법 수정판)

echo "================================================================================"
echo "🔑 SSH 키 기반 RebootProgram 설정 (올바른 문법)"
echo "================================================================================"
echo ""

# SSH 접속 정보
echo "📝 SSH 접속 정보 입력"
echo "--------------------------------------------------------------------------------"
read -p "노드 SSH 사용자 이름 (기본값: root): " SSH_USER
SSH_USER=${SSH_USER:-root}

read -sp "노드 SSH 비밀번호 (키 복사 시 1회만 사용): " SSH_PASSWORD
echo ""
echo ""

if [ -z "$SSH_PASSWORD" ]; then
    echo "❌ 비밀번호가 필요합니다"
    exit 1
fi

echo "✅ 접속 정보 입력 완료"
echo "   사용자: $SSH_USER"
echo ""

# scontrol 경로
SCONTROL_PATH=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
echo "📍 scontrol 경로: $SCONTROL_PATH"
echo ""

# 1. SSH 키 생성 (이미 있으면 건너뜀)
echo "🔑 Step 1/5: SSH 키 생성"
echo "--------------------------------------------------------------------------------"
if [ -f "$HOME/.ssh/id_rsa" ]; then
    echo "✅ SSH 키가 이미 존재합니다: $HOME/.ssh/id_rsa"
else
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
    echo "✅ SSH 키 생성 완료"
fi
echo ""

# 2. sshpass 설치
echo "📦 Step 2/5: sshpass 설치 확인"
echo "--------------------------------------------------------------------------------"
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  sshpass 설치 필요"
    read -p "sshpass를 설치하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y sshpass
        echo "✅ sshpass 설치 완료"
    else
        echo "❌ sshpass 없이는 자동 키 복사가 불가능합니다"
        exit 1
    fi
else
    echo "✅ sshpass 설치되어 있음"
fi
echo ""

# 3. 모든 노드에 SSH 키 복사
echo "📤 Step 3/5: 모든 노드에 SSH 키 복사"
echo "--------------------------------------------------------------------------------"

NODES=$(sinfo -N -h -o "%N" | sort -u)
SUCCESS_COUNT=0
FAIL_COUNT=0

echo "감지된 노드:"
echo "$NODES"
echo ""

for NODE in $NODES; do
    echo "처리 중: ${SSH_USER}@${NODE}"
    
    # SSH 키 복사
    if sshpass -p "$SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${NODE} 2>/dev/null; then
        echo "  ✅ 키 복사 성공: ${NODE}"
        ((SUCCESS_COUNT++))
        
        # 연결 테스트
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 ${SSH_USER}@${NODE} "echo 'SSH Key OK'" 2>/dev/null; then
            echo "  ✅ 키 인증 테스트 성공"
        else
            echo "  ⚠️  키 인증 테스트 실패"
        fi
    else
        echo "  ❌ 실패: ${NODE}"
        ((FAIL_COUNT++))
    fi
    echo ""
done

echo "--------------------------------------------------------------------------------"
echo "결과: 성공 ${SUCCESS_COUNT}개, 실패 ${FAIL_COUNT}개"
echo ""

if [ $SUCCESS_COUNT -eq 0 ]; then
    echo "❌ 모든 노드에 SSH 키 복사 실패"
    exit 1
fi

# 4. RebootProgram 스크립트 생성
echo "📝 Step 4/5: RebootProgram 스크립트 생성"
echo "--------------------------------------------------------------------------------"
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

sudo tee $REBOOT_SCRIPT > /dev/null <<EOF
#!/bin/bash
# Slurm Node Reboot Script with SSH Key Authentication
# scontrol reboot 명령어로 호출됩니다
#
# 사용법: $REBOOT_SCRIPT <node_name>
# 예: $REBOOT_SCRIPT node001

# 인자 파싱
NODE_NAME=\$1
SSH_USER="${SSH_USER}"

if [ -z "\$NODE_NAME" ]; then
    echo "Error: Node name is required"
    echo "Usage: \$0 <node_name>"
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
log_msg "Reboot request received"
log_msg "Node: \$NODE_NAME"
log_msg "User: \$SSH_USER"
log_msg "=========================================="

# SSH 키 기반 인증으로 재부팅
log_msg "Attempting SSH reboot: \${SSH_USER}@\${NODE_NAME}"

# SSH 명령 실행 (재부팅 명령을 백그라운드로)
if ssh -o StrictHostKeyChecking=no \
       -o ConnectTimeout=5 \
       -o BatchMode=yes \
       \${SSH_USER}@\${NODE_NAME} \
       "nohup sudo /sbin/reboot >/dev/null 2>&1 &" 2>&1 | tee -a \$LOG_FILE; then
    
    log_msg "✅ Successfully sent reboot command to \$NODE_NAME"
    log_msg "Node \$NODE_NAME should reboot shortly"
    exit 0
else
    log_msg "❌ SSH command failed for \$NODE_NAME"
    
    # Fallback: 로컬 노드인지 확인
    if [ "\$NODE_NAME" == "\$(hostname)" ] || [ "\$NODE_NAME" == "\$(hostname -s)" ]; then
        log_msg "Attempting local reboot (node is controller)"
        /sbin/reboot
    fi
    
    exit 1
fi
EOF

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ 스크립트 생성 완료: $REBOOT_SCRIPT"
echo ""

# 스크립트 테스트
echo "🧪 스크립트 테스트"
echo "--------------------------------------------------------------------------------"
FIRST_NODE=$(echo "$NODES" | head -1)
echo "테스트 노드: $FIRST_NODE"
echo ""

read -p "스크립트를 테스트하시겠습니까? (실제 재부팅됨!) (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "테스트 실행 중..."
    sudo $REBOOT_SCRIPT $FIRST_NODE
    
    echo ""
    echo "로그 확인:"
    sudo tail -10 /var/log/slurm/node_reboot.log
else
    echo "⚠️  테스트를 건너뜁니다"
fi
echo ""

# 5. slurm.conf 업데이트
echo "📝 Step 5/5: slurm.conf 업데이트"
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
        echo ""
        echo "RebootProgram 설정 확인:"
        $SCONTROL_PATH show config | grep -i reboot
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
echo "  - SSH 키: $HOME/.ssh/id_rsa"
echo "  - RebootProgram: $REBOOT_SCRIPT"
echo "  - 로그 파일: /var/log/slurm/node_reboot.log"
echo ""
echo "🔒 보안:"
echo "  ✅ SSH 키 기반 인증"
echo "  ✅ 비밀번호 저장 불필요"
echo ""
echo "🧪 테스트 방법:"
echo ""
echo "  1. SSH 연결 테스트:"
echo "     ssh ${SSH_USER}@${FIRST_NODE} 'echo SSH OK'"
echo ""
echo "  2. RebootProgram 스크립트 직접 실행:"
echo "     sudo $REBOOT_SCRIPT ${FIRST_NODE}"
echo ""
echo "  3. scontrol 명령어로 재부팅:"
echo "     $SCONTROL_PATH reboot ${FIRST_NODE} reason='manual_test'"
echo ""
echo "  4. sudo로 scontrol 실행:"
echo "     sudo $SCONTROL_PATH reboot ${FIRST_NODE} reason='sudo_test'"
echo ""
echo "  5. 웹 대시보드에서 Reboot 버튼 클릭"
echo "     → http://localhost:3010 → Node Management"
echo ""
echo "📄 로그 실시간 확인:"
echo "  sudo tail -f /var/log/slurm/node_reboot.log"
echo ""
echo "📄 Slurm 컨트롤러 로그:"
echo "  sudo tail -f /var/log/slurm/slurmctld.log | grep -i reboot"
echo ""
