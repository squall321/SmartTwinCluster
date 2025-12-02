#!/bin/bash

echo "================================================================================"
echo "🔑 SSH 키 기반 인증 설정 (권장)"
echo "================================================================================"
echo ""
echo "이 방법이 비밀번호 방식보다 안전합니다"
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
echo ""

# 1. SSH 키 생성 (이미 있으면 건너뜀)
echo "🔑 Step 1/4: SSH 키 생성"
echo "--------------------------------------------------------------------------------"
if [ -f "$HOME/.ssh/id_rsa" ]; then
    echo "✅ SSH 키가 이미 존재합니다: $HOME/.ssh/id_rsa"
else
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
    echo "✅ SSH 키 생성 완료"
fi
echo ""

# 2. 모든 노드에 SSH 키 복사
echo "📤 Step 2/4: 모든 노드에 SSH 키 복사"
echo "--------------------------------------------------------------------------------"

# sshpass 설치 확인
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  sshpass 설치 필요 (SSH 키 복사를 위해)"
    read -p "sshpass를 설치하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y sshpass
    else
        echo "❌ sshpass 없이는 자동 키 복사가 불가능합니다"
        exit 1
    fi
fi

# 모든 노드 가져오기
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
        echo "  ✅ 성공: ${NODE}"
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

# 3. RebootProgram 스크립트 생성 (SSH 키 버전)
echo "📝 Step 3/4: RebootProgram 스크립트 생성"
echo "--------------------------------------------------------------------------------"
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

sudo tee $REBOOT_SCRIPT > /dev/null <<EOF
#!/bin/bash
# Slurm Node Reboot Script with SSH Key Authentication
# 이 스크립트는 scontrol reboot 명령어로 호출됩니다

NODE_NAME=\$1
SSH_USER="${SSH_USER}"

if [ -z "\$NODE_NAME" ]; then
    echo "Error: Node name is required"
    exit 1
fi

# 로그 파일
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p \$(dirname \$LOG_FILE)

# 로그 기록
echo "\$(date '+%Y-%m-%d %H:%M:%S') - Reboot request for node: \$NODE_NAME (user: \$SSH_USER)" >> \$LOG_FILE

# SSH 키 기반 인증으로 재부팅
echo "\$(date '+%Y-%m-%d %H:%M:%S') - Attempting SSH reboot for \${SSH_USER}@\${NODE_NAME}" >> \$LOG_FILE

# SSH 명령 실행
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \${SSH_USER}@\${NODE_NAME} "sudo /sbin/reboot" 2>&1 >> \$LOG_FILE; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ✅ Successfully sent reboot command to \$NODE_NAME" >> \$LOG_FILE
    exit 0
else
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ❌ SSH reboot failed for \$NODE_NAME" >> \$LOG_FILE
    
    # Fallback: 로컬 재부팅 시도
    if [ "\$NODE_NAME" == "\$(hostname)" ] || [ "\$NODE_NAME" == "\$(hostname -s)" ]; then
        echo "\$(date '+%Y-%m-%d %H:%M:%S') - Attempting local reboot" >> \$LOG_FILE
        /sbin/reboot
    fi
    
    exit 1
fi
EOF

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ 스크립트 생성 완료: $REBOOT_SCRIPT"
echo ""

# 4. slurm.conf 업데이트
echo "📝 Step 4/4: slurm.conf 업데이트"
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
echo "  - SSH 키: $HOME/.ssh/id_rsa (컨트롤러)"
echo "  - RebootProgram: $REBOOT_SCRIPT"
echo "  - 로그 파일: /var/log/slurm/node_reboot.log"
echo ""
echo "🔒 보안:"
echo "  ✅ SSH 키 기반 인증 (비밀번호 저장 불필요)"
echo "  ✅ 안전하고 권장되는 방식"
echo ""
echo "🧪 테스트:"
echo "  1. SSH 연결 테스트:"
echo "     ssh ${SSH_USER}@$(echo $NODES | head -1) 'echo SSH OK'"
echo ""
echo "  2. 스크립트 직접 실행:"
echo "     sudo $REBOOT_SCRIPT $(echo $NODES | head -1)"
echo ""
echo "  3. scontrol 명령어:"
echo "     sudo scontrol reboot $(echo $NODES | head -1) reason='test'"
echo ""
echo "  4. 웹 대시보드에서 Reboot 버튼 클릭"
echo ""
echo "📄 로그 확인:"
echo "  sudo tail -f /var/log/slurm/node_reboot.log"
echo ""
