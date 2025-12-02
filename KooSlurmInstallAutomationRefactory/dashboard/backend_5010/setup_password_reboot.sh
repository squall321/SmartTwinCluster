#!/bin/bash

echo "================================================================================"
echo "🔧 SSH 비밀번호 기반 RebootProgram 설정"
echo "================================================================================"
echo ""
echo "이 스크립트는 SSH 비밀번호를 사용하여 원격 노드를 재부팅합니다"
echo ""

# SSH 접속 정보 입력
echo "📝 SSH 접속 정보 입력"
echo "--------------------------------------------------------------------------------"
read -p "노드 SSH 사용자 이름 (기본값: root): " SSH_USER
SSH_USER=${SSH_USER:-root}

read -sp "노드 SSH 비밀번호: " SSH_PASSWORD
echo ""
echo ""

if [ -z "$SSH_PASSWORD" ]; then
    echo "❌ 비밀번호가 필요합니다"
    exit 1
fi

echo "✅ 접속 정보 입력 완료"
echo "   사용자: $SSH_USER"
echo ""

# 1. sshpass 설치 확인
echo "📦 Step 1/5: sshpass 설치 확인"
echo "--------------------------------------------------------------------------------"
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  sshpass가 설치되어 있지 않습니다"
    echo ""
    read -p "sshpass를 설치하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y sshpass
        echo "✅ sshpass 설치 완료"
    else
        echo "❌ sshpass 없이는 비밀번호 기반 SSH 자동화가 불가능합니다"
        echo ""
        echo "대안: SSH 키 기반 인증 사용"
        echo "  ./setup_ssh_key.sh"
        exit 1
    fi
else
    echo "✅ sshpass 설치되어 있음"
fi
echo ""

# 2. SSH 연결 테스트
echo "🔗 Step 2/5: SSH 연결 테스트"
echo "--------------------------------------------------------------------------------"
FIRST_NODE=$(sinfo -N -h -o "%N" | head -1)
echo "테스트 노드: $FIRST_NODE"
echo ""

if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${FIRST_NODE} "echo 'SSH OK'" 2>/dev/null; then
    echo "✅ SSH 연결 성공: ${SSH_USER}@${FIRST_NODE}"
else
    echo "❌ SSH 연결 실패"
    echo ""
    echo "확인 사항:"
    echo "  1. 노드 주소가 올바른가? ping ${FIRST_NODE}"
    echo "  2. SSH 서비스가 실행 중인가?"
    echo "  3. 사용자 이름과 비밀번호가 올바른가?"
    exit 1
fi
echo ""

# 3. 비밀번호를 안전하게 저장 (파일 방식)
echo "🔒 Step 3/5: 비밀번호 안전 저장"
echo "--------------------------------------------------------------------------------"
PASSWORD_FILE="/usr/local/slurm/etc/.node_ssh_password"
echo "$SSH_PASSWORD" | sudo tee $PASSWORD_FILE > /dev/null
sudo chmod 600 $PASSWORD_FILE
sudo chown root:root $PASSWORD_FILE
echo "✅ 비밀번호 저장 완료: $PASSWORD_FILE"
echo "   권한: $(sudo ls -l $PASSWORD_FILE)"
echo ""

# 4. RebootProgram 스크립트 생성
echo "📝 Step 4/5: RebootProgram 스크립트 생성"
echo "--------------------------------------------------------------------------------"
REBOOT_SCRIPT="/usr/local/slurm/sbin/slurm_reboot_node.sh"

sudo tee $REBOOT_SCRIPT > /dev/null <<EOF
#!/bin/bash
# Slurm Node Reboot Script with Password Authentication
# 이 스크립트는 scontrol reboot 명령어로 호출됩니다

NODE_NAME=\$1
SSH_USER="${SSH_USER}"
PASSWORD_FILE="${PASSWORD_FILE}"

if [ -z "\$NODE_NAME" ]; then
    echo "Error: Node name is required"
    exit 1
fi

# 로그 파일
LOG_FILE="/var/log/slurm/node_reboot.log"
mkdir -p \$(dirname \$LOG_FILE)

# 로그 기록
echo "\$(date '+%Y-%m-%d %H:%M:%S') - Reboot request for node: \$NODE_NAME" >> \$LOG_FILE

# 비밀번호 읽기
if [ ! -f "\$PASSWORD_FILE" ]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Password file not found: \$PASSWORD_FILE" >> \$LOG_FILE
    exit 1
fi

SSH_PASSWORD=\$(cat \$PASSWORD_FILE)

# SSH를 통한 재부팅
echo "\$(date '+%Y-%m-%d %H:%M:%S') - Attempting SSH reboot for \${SSH_USER}@\${NODE_NAME}" >> \$LOG_FILE

if sshpass -p "\$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \${SSH_USER}@\${NODE_NAME} "sudo /sbin/reboot" 2>&1 >> \$LOG_FILE; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ✅ Successfully sent reboot command to \$NODE_NAME" >> \$LOG_FILE
    exit 0
else
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - ❌ SSH reboot failed for \$NODE_NAME" >> \$LOG_FILE
    exit 1
fi
EOF

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ 스크립트 생성 완료: $REBOOT_SCRIPT"
echo ""

# 5. 스크립트 테스트
echo "🧪 Step 5/5: 스크립트 테스트"
echo "--------------------------------------------------------------------------------"
read -p "스크립트를 테스트하시겠습니까? (실제 재부팅됨!) (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "테스트 실행 중: sudo $REBOOT_SCRIPT $FIRST_NODE"
    sudo $REBOOT_SCRIPT $FIRST_NODE
    
    echo ""
    echo "로그 확인:"
    sudo tail -5 /var/log/slurm/node_reboot.log
else
    echo "⚠️  테스트를 건너뜁니다"
fi
echo ""

# 6. slurm.conf 업데이트
echo "📝 Step 6/6: slurm.conf 업데이트"
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

# 7. slurmctld 재시작
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
echo "  - 비밀번호 파일: $PASSWORD_FILE (root만 읽기 가능)"
echo "  - 로그 파일: /var/log/slurm/node_reboot.log"
echo ""
echo "🔒 보안 주의사항:"
echo "  - 비밀번호가 파일에 평문으로 저장됩니다"
echo "  - root만 읽을 수 있도록 권한 설정됨 (600)"
echo "  - 프로덕션 환경에서는 SSH 키 기반 인증 권장"
echo ""
echo "🧪 테스트:"
echo "  1. 스크립트 직접 실행:"
echo "     sudo $REBOOT_SCRIPT $FIRST_NODE"
echo ""
echo "  2. scontrol 명령어:"
echo "     sudo scontrol reboot $FIRST_NODE reason='test'"
echo ""
echo "  3. 웹 대시보드에서 Reboot 버튼 클릭"
echo ""
echo "📄 로그 확인:"
echo "  sudo tail -f /var/log/slurm/node_reboot.log"
echo ""
