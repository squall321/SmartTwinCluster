#!/bin/bash
################################################################################
# setup_reboot_program.sh를 YAML 기반으로 리팩토링하는 스크립트 (수정본)
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "🔧 setup_reboot_program.sh YAML 기반 리팩토링"
echo "================================================================================"
echo ""

# 1. YAML 파일 확인
echo "📝 Step 1: my_multihead_cluster.yaml 확인..."

if [ ! -f "my_multihead_cluster.yaml" ]; then
    echo "❌ my_multihead_cluster.yaml 파일을 찾을 수 없습니다!"
    exit 1
fi

# admin_user 확인
if ! grep -q "admin_user:" my_multihead_cluster.yaml; then
    echo "⚠️  admin_user가 없어서 추가합니다..."
    sed -i '/^users:/a\  admin_user: koopark' my_multihead_cluster.yaml
    echo "✅ admin_user: koopark 추가 완료"
else
    echo "✅ admin_user가 이미 존재합니다"
    grep "admin_user:" my_multihead_cluster.yaml
fi
echo ""

# 2. setup_reboot_program.sh 백업
echo "📝 Step 2: 기존 setup_reboot_program.sh 백업..."
if [ -f "setup_reboot_program.sh" ]; then
    cp setup_reboot_program.sh setup_reboot_program.sh.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ 백업 완료"
else
    echo "⚠️  setup_reboot_program.sh 파일이 없습니다 (새로 생성합니다)"
fi
echo ""

# 3. 새로운 YAML 기반 setup_reboot_program.sh 생성
echo "📝 Step 3: YAML 기반 setup_reboot_program.sh 생성..."

cat > setup_reboot_program.sh << 'MAINSCRIPT'
#!/bin/bash
################################################################################
# RebootProgram 설정 - YAML 기반
# my_multihead_cluster.yaml에서 설정을 읽어와서 동적으로 구성합니다
################################################################################

set -e

echo "================================================================================"
echo "🔄 Step: RebootProgram 설정 (YAML 기반)"
echo "================================================================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE="${SCRIPT_DIR}/my_multihead_cluster.yaml"

# YAML 파일 확인
if [ ! -f "$YAML_FILE" ]; then
    echo "❌ $YAML_FILE 파일을 찾을 수 없습니다!"
    exit 1
fi

echo "📖 YAML 설정 읽는 중..."

# Python으로 YAML 파싱 (간단한 방법)
YAML_VALUES=$(python3 << 'PYEOF'
import yaml
import sys

try:
    with open('my_multihead_cluster.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    admin_user = config.get('users', {}).get('admin_user', 'koopark')
    slurm_user = config.get('users', {}).get('slurm_user', 'slurm')
    install_path = config.get('slurm_config', {}).get('install_path', '/usr/local/slurm')
    reboot_cmd = config.get('slurm_config', {}).get('reboot_program', '/sbin/reboot')
    
    print(f"{admin_user}|{slurm_user}|{install_path}|{reboot_cmd}")
except Exception as e:
    print("koopark|slurm|/usr/local/slurm|/sbin/reboot")
    sys.exit(0)
PYEOF
)

# 파싱 결과 분리
IFS='|' read -r ADMIN_USER SLURM_USER INSTALL_PATH REBOOT_CMD <<< "$YAML_VALUES"

echo "✅ YAML 설정:"
echo "   - Admin User: $ADMIN_USER"
echo "   - Slurm User: $SLURM_USER"
echo "   - Install Path: $INSTALL_PATH"
echo "   - Reboot Command: $REBOOT_CMD"
echo ""

# 경로 설정
SCONTROL_PATH="${INSTALL_PATH}/bin/scontrol"
REBOOT_SCRIPT="${INSTALL_PATH}/sbin/slurm_reboot_node.sh"
SLURM_CONF="${INSTALL_PATH}/etc/slurm.conf"

echo "📝 RebootProgram 스크립트 생성 중..."

# RebootProgram 스크립트 생성
sudo tee $REBOOT_SCRIPT > /dev/null << 'INNEREOF'
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

# ADMIN_USER 사용자로 SSH 실행
if su - ADMIN_USER -c "ssh -o StrictHostKeyChecking=no -o BatchMode=yes ADMIN_USER@${NODE_NAME} 'sudo REBOOT_CMD'" >> $LOG_FILE 2>&1; then
    log_msg "✅ Reboot command sent successfully"
    exit 0
else
    log_msg "❌ SSH command failed"
    exit 1
fi
INNEREOF

# 변수 치환
sudo sed -i "s/ADMIN_USER/${ADMIN_USER}/g" $REBOOT_SCRIPT
sudo sed -i "s|REBOOT_CMD|${REBOOT_CMD}|g" $REBOOT_SCRIPT

sudo chmod +x $REBOOT_SCRIPT
sudo chown root:root $REBOOT_SCRIPT
echo "✅ RebootProgram 스크립트 생성: $REBOOT_SCRIPT"
echo ""

# slurm.conf에 RebootProgram 추가
echo "📝 slurm.conf 확인 중..."
if [ -f "$SLURM_CONF" ]; then
    if ! grep -q "^RebootProgram=" "$SLURM_CONF"; then
        echo "RebootProgram=$REBOOT_SCRIPT" | sudo tee -a "$SLURM_CONF" > /dev/null
        echo "✅ slurm.conf에 RebootProgram 추가"
    else
        CURRENT_REBOOT=$(grep "^RebootProgram=" "$SLURM_CONF" | cut -d'=' -f2)
        if [ "$CURRENT_REBOOT" != "$REBOOT_SCRIPT" ]; then
            sudo sed -i "s|^RebootProgram=.*|RebootProgram=$REBOOT_SCRIPT|" "$SLURM_CONF"
            echo "✅ slurm.conf의 RebootProgram 업데이트: $REBOOT_SCRIPT"
        else
            echo "✅ RebootProgram이 이미 올바르게 설정되어 있습니다"
        fi
    fi
else
    echo "⚠️  $SLURM_CONF 파일이 아직 생성되지 않았습니다"
    echo "   (configure_slurm_from_yaml.py 실행 후 자동 생성됩니다)"
fi
echo ""

# sudoers 설정 (scontrol reboot 권한)
echo "🔒 sudoers 설정 중..."
sudo tee /etc/sudoers.d/slurm-dashboard-scontrol > /dev/null << SUDOEOF
# Slurm Dashboard - scontrol reboot permission
${ADMIN_USER} ALL=(ALL) NOPASSWD: ${SCONTROL_PATH} reboot *
${ADMIN_USER} ALL=(ALL) NOPASSWD: ${SCONTROL_PATH}
SUDOEOF

sudo chmod 0440 /etc/sudoers.d/slurm-dashboard-scontrol
echo "✅ sudoers 설정 완료"
echo ""

# 계산 노드 목록 가져오기
echo "📝 계산 노드 목록 가져오는 중..."
COMPUTE_NODES=$(python3 << 'NODEEOF'
import yaml
try:
    with open('my_multihead_cluster.yaml', 'r') as f:
        config = yaml.safe_load(f)
    nodes = config.get('nodes', {}).get('compute_nodes', [])
    for node in nodes:
        print(node.get('hostname', ''))
except:
    pass
NODEEOF
)

if [ -z "$COMPUTE_NODES" ]; then
    echo "⚠️  계산 노드를 찾을 수 없습니다"
else
    echo "✅ 계산 노드 목록:"
    echo "$COMPUTE_NODES" | sed 's/^/   - /'
fi
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
for node in $COMPUTE_NODES; do
    [ -n "$node" ] && echo "   ssh-copy-id ${ADMIN_USER}@${node}"
done
echo ""
echo "3. 각 노드에서 sudo 권한 설정 (비밀번호 없이 재부팅):"
for node in $COMPUTE_NODES; do
    if [ -n "$node" ]; then
        echo "   # ${node}"
        echo "   ssh ${ADMIN_USER}@${node}"
        echo "   echo '${ADMIN_USER} ALL=(ALL) NOPASSWD: ${REBOOT_CMD}' | sudo tee /etc/sudoers.d/${ADMIN_USER}-reboot"
        echo "   sudo chmod 0440 /etc/sudoers.d/${ADMIN_USER}-reboot"
        echo "   exit"
        echo ""
    fi
done
echo ""
echo "4. 테스트:"
FIRST_NODE=$(echo "$COMPUTE_NODES" | head -n1)
if [ -n "$FIRST_NODE" ]; then
    echo "   ssh ${ADMIN_USER}@${FIRST_NODE} 'sudo ${REBOOT_CMD}'"
fi
echo ""
echo "💡 자동화 스크립트가 필요하면 dashboard/backend_5010/setup_ssh_for_user.sh 참고"
echo ""
echo "================================================================================"
echo "✅ RebootProgram 설정 완료!"
echo "================================================================================"
MAINSCRIPT

chmod +x setup_reboot_program.sh
echo "✅ 새로운 setup_reboot_program.sh 생성 완료"
echo ""

# 4. 요약
echo "================================================================================"
echo "✅ 리팩토링 완료!"
echo "================================================================================"
echo ""
echo "📝 변경 사항:"
echo "  1. setup_reboot_program.sh를 YAML 기반으로 재작성"
echo "     - 하드코딩 제거"
echo "     - YAML에서 admin_user, install_path, reboot_program 읽기"
echo "     - 계산 노드 목록 동적 생성"
echo ""
echo "📋 다음 단계:"
echo "  1. 테스트:"
echo "     ./setup_reboot_program.sh"
echo ""
echo "  2. 확인:"
echo "     cat /usr/local/slurm/sbin/slurm_reboot_node.sh"
echo "     cat /etc/sudoers.d/slurm-dashboard-scontrol"
echo ""
echo "💾 백업 파일: setup_reboot_program.sh.backup.*"
echo ""
