#!/bin/bash
################################################################################
# Munge 자동 설치 스크립트 - SSH 키 기반 (비밀번호 불필요)
# SSH 키가 설정되어 있으면 비밀번호 입력 없이 작동
#
# Usage: ./install_munge_auto.sh [CONFIG_FILE]
#   CONFIG_FILE: Path to YAML config file (default: my_cluster.yaml)
################################################################################

set -e

# 설정 파일 파라미터 (기본값: my_cluster.yaml)
CONFIG_FILE="${1:-my_cluster.yaml}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

echo "📋 설정 파일: $CONFIG_FILE"
echo ""

# 설정 파일에서 노드 정보 읽기
mapfile -t NODES < <(CONFIG_FILE="$CONFIG_FILE" python3 << EOFPY
import yaml
import os
config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['ip_address'])
EOFPY
)

mapfile -t NODE_NAMES < <(CONFIG_FILE="$CONFIG_FILE" python3 << EOFPY
import yaml
import os
config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['hostname'])
EOFPY
)

USER_NAME=$(CONFIG_FILE="$CONFIG_FILE" python3 << EOFPY
import yaml
import os
config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

# Support both single-head (controller) and multi-head (controllers) formats
nodes = config['nodes']
if 'controllers' in nodes and isinstance(nodes['controllers'], list):
    # Multi-head format: use first controller
    print(nodes['controllers'][0]['ssh_user'])
elif 'controller' in nodes:
    # Single-head format
    print(nodes['controller']['ssh_user'])
else:
    raise KeyError('No controller or controllers found in nodes')
EOFPY
)

echo "================================================================================"
echo "🔐 Munge 자동 설치 (SSH 키 기반)"
echo "================================================================================"
echo ""
echo "이 스크립트는 다음을 자동으로 수행합니다:"
echo "  1. 컨트롤러에 Munge 설치 및 키 생성"
echo "  2. 계산 노드에 Munge 설치"
echo "  3. Munge 키 배포"
echo "  4. 서비스 시작 및 검증"
echo ""
echo "대상 노드:"
echo "  - 컨트롤러: smarttwincluster (localhost)"
for i in "${!NODES[@]}"; do
  echo "  - ${NODE_NAMES[$i]}: ${NODES[$i]}"
done
echo ""

# SSH 키 확인
echo "🔍 SSH 키 설정 확인 중..."
if [ ! -f ~/.ssh/id_rsa ]; then
    echo ""
    echo "⚠️  SSH 키가 없습니다!"
    echo ""
    echo "💡 먼저 SSH 키를 설정하세요:"
    echo "   ./setup_ssh_passwordless.sh"
    echo ""
    read -p "SSH 키 없이 계속하시겠습니까? (sshpass 사용) (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "취소되었습니다."
        echo ""
        echo "SSH 키 설정 후 다시 실행하세요:"
        echo "  ./setup_ssh_passwordless.sh"
        exit 0
    fi
    
    USE_SSHPASS=true
else
    # SSH 키로 접속 테스트
    echo -n "  SSH 키 테스트 (node1): "
    if ssh -o BatchMode=yes -o ConnectTimeout=5 $USER_NAME@${NODES[0]} "echo OK" > /dev/null 2>&1; then
        echo "✅ SSH 키 작동"
        USE_SSHPASS=false
    else
        echo "⚠️  SSH 키가 설정되지 않음"
        echo ""
        echo "💡 먼저 SSH 키를 설정하는 것을 권장합니다:"
        echo "   ./setup_ssh_passwordless.sh"
        echo ""
        read -p "sshpass를 사용하시겠습니까? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            USE_SSHPASS=true
        else
            echo "취소되었습니다."
            exit 0
        fi
    fi
fi

echo ""

# sshpass 사용 시 비밀번호 설정
if [ "$USE_SSHPASS" = true ]; then
    # 설정 파일에서 비밀번호 읽기
    PASSWORD=$(CONFIG_FILE="$CONFIG_FILE" python3 << EOFPY
import yaml
import os
config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)
password = config.get('cluster_info', {}).get('ssh_password', '')
print(password if password else '')
EOFPY
)

    if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "your_password_here" ]; then
        echo "================================================================================"
        echo "📝 비밀번호 입력"
        echo "================================================================================"
        echo ""
        echo "⚠️  $CONFIG_FILE에 ssh_password가 설정되지 않았습니다."
        echo "노드들의 비밀번호를 입력하세요."
        echo "(모든 노드의 비밀번호가 같다고 가정합니다)"
        echo ""

        # 비밀번호 입력
        read -s -p "비밀번호: " PASSWORD
        echo ""

        if [ -z "$PASSWORD" ]; then
          echo "❌ 비밀번호가 비어있습니다."
          exit 1
        fi

        # 비밀번호 확인
        read -s -p "비밀번호 확인: " PASSWORD_CONFIRM
        echo ""

        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
          echo "❌ 비밀번호가 일치하지 않습니다."
          exit 1
        fi

        echo ""
        echo "✅ 비밀번호 입력 완료"
    else
        echo "✅ $CONFIG_FILE에서 SSH 비밀번호 로드됨"
    fi

    # sshpass 설치 확인
    if ! command -v sshpass &> /dev/null; then
        echo ""
        echo "📦 sshpass 설치 중..."
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y sshpass > /dev/null 2>&1 || sudo yum install -y sshpass > /dev/null 2>&1

        if ! command -v sshpass &> /dev/null; then
            echo "❌ sshpass 설치 실패"
            echo "💡 수동으로 설치하세요: sudo apt install sshpass"
            exit 1
        fi
    fi
fi

echo ""
read -p "계속하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# SSH/SCP 명령어 래퍼 함수
ssh_cmd() {
    local host=$1
    shift
    
    if [ "$USE_SSHPASS" = true ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$host" "$@"
    else
        ssh -o StrictHostKeyChecking=no "$host" "$@"
    fi
}

scp_cmd() {
    local src=$1
    local dest=$2
    
    if [ "$USE_SSHPASS" = true ]; then
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$src" "$dest"
    else
        scp -o StrictHostKeyChecking=no "$src" "$dest"
    fi
}

echo ""
echo "================================================================================"
echo "1단계: 컨트롤러 Munge 설치"
echo "================================================================================"
echo ""

chmod +x install_munge_manual.sh
sudo ./install_munge_manual.sh controller

if [ $? -ne 0 ]; then
    echo "❌ 컨트롤러 Munge 설치 실패"
    exit 1
fi

echo ""
echo "✅ 컨트롤러 Munge 설치 완료"

echo ""
echo "================================================================================"
echo "2단계: 계산 노드 Munge 설치"
echo "================================================================================"
echo ""

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo "📌 $node_name ($node)"
    echo "────────────────────────────────────────"
    
    # 연결 테스트
    echo "  [1/5] SSH 연결 테스트..."
    if ! ssh_cmd $USER_NAME@$node "echo OK" > /dev/null 2>&1; then
        echo "  ❌ SSH 연결 실패"
        continue
    fi
    echo "  ✅ 연결 성공"
    
    # 스크립트 복사
    echo "  [2/5] 설치 스크립트 및 오프라인 패키지 복사..."
    scp_cmd install_munge_manual.sh $USER_NAME@$node:/tmp/ > /dev/null 2>&1

    # 오프라인 패키지가 있으면 함께 복사
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    OFFLINE_PKGS="$SCRIPT_DIR/offline_packages/apt_packages"
    if [ -d "$OFFLINE_PKGS" ] && [ -f "$OFFLINE_PKGS/munge_0.5.14-6_amd64.deb" ]; then
        ssh_cmd $USER_NAME@$node "mkdir -p /tmp/offline_packages/apt_packages" > /dev/null 2>&1
        scp_cmd "$OFFLINE_PKGS/libmunge2_0.5.14-6_amd64.deb" \
                "$OFFLINE_PKGS/munge_0.5.14-6_amd64.deb" \
                "$OFFLINE_PKGS/libmunge-dev_0.5.14-6_amd64.deb" \
                $USER_NAME@$node:/tmp/offline_packages/apt_packages/ > /dev/null 2>&1
        echo "  ✓ 오프라인 패키지 복사 완료"
    fi

    # Munge 설치
    echo "  [3/5] Munge 설치 중..."
    MUNGE_INSTALL_CMD='cd /tmp && chmod +x install_munge_manual.sh && ./install_munge_manual.sh'

    if [ "$USE_SSHPASS" = true ]; then
        # 방법 1: SUDO_ASKPASS + base64 (가장 안정적)
        ENCODED_PW=$(echo -n "$PASSWORD" | base64)
        ssh_cmd $USER_NAME@$node \
            "echo '#!/bin/bash' > /tmp/askpass.sh && echo 'echo $ENCODED_PW | base64 -d' >> /tmp/askpass.sh && chmod +x /tmp/askpass.sh && export SUDO_ASKPASS=/tmp/askpass.sh && sudo -A bash -c '$MUNGE_INSTALL_CMD'; rm -f /tmp/askpass.sh" > /dev/null 2>&1
    else
        ssh_cmd $USER_NAME@$node "sudo bash -c '$MUNGE_INSTALL_CMD'" > /dev/null 2>&1
    fi
    
    # 키 복사 (sudo 필요 없음!)
    echo "  [4/5] Munge 키 복사..."
    sudo cp /etc/munge/munge.key /tmp/munge.key.tmp
    sudo chown $USER:$USER /tmp/munge.key.tmp
    scp_cmd /tmp/munge.key.tmp $USER_NAME@$node:/tmp/munge.key > /dev/null 2>&1
    sudo rm /tmp/munge.key.tmp
    
    # 키 설치 및 서비스 시작
    echo "  [5/5] Munge 키 설치 및 서비스 시작..."
    MUNGE_KEY_CMD='mv /tmp/munge.key /etc/munge/ && chown munge:munge /etc/munge/munge.key && chmod 400 /etc/munge/munge.key && systemctl restart munge'

    if [ "$USE_SSHPASS" = true ]; then
        # SUDO_ASKPASS + base64 방식
        ENCODED_PW=$(echo -n "$PASSWORD" | base64)
        ssh_cmd $USER_NAME@$node \
            "echo '#!/bin/bash' > /tmp/askpass.sh && echo 'echo $ENCODED_PW | base64 -d' >> /tmp/askpass.sh && chmod +x /tmp/askpass.sh && export SUDO_ASKPASS=/tmp/askpass.sh && sudo -A bash -c '$MUNGE_KEY_CMD'; rm -f /tmp/askpass.sh" > /dev/null 2>&1
    else
        ssh_cmd $USER_NAME@$node "sudo bash -c '$MUNGE_KEY_CMD'" > /dev/null 2>&1
    fi
    
    echo "  ✅ $node_name 완료"
    echo ""
done

echo "================================================================================"
echo "3단계: Munge 검증"
echo "================================================================================"
echo ""

all_success=true

# 컨트롤러 검증
echo -n "📌 컨트롤러 (smarttwincluster): "
if munge -n | unmunge > /dev/null 2>&1; then
    echo "✅ 정상"
else
    echo "❌ 실패"
    all_success=false
fi

# 계산 노드 검증
for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo -n "📌 $node_name ($node): "
    
    result=$(ssh_cmd $USER_NAME@$node "munge -n | unmunge 2>&1" 2>/dev/null)
    
    if echo "$result" | grep -q "Success"; then
        echo "✅ 정상"
    else
        echo "❌ 실패"
        all_success=false
    fi
done

echo ""
echo "================================================================================"
echo "4단계: 노드 간 인증 테스트"
echo "================================================================================"
echo ""

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo -n "📌 컨트롤러 → $node_name: "
    
    if munge -n | ssh_cmd $USER_NAME@$node unmunge 2>/dev/null | grep -q "Success"; then
        echo "✅ 인증 성공"
    else
        echo "❌ 인증 실패"
        all_success=false
    fi
done

echo ""
echo "================================================================================"

if [ "$all_success" = true ]; then
    echo "🎉 Munge 설치 및 검증 완료!"
    echo "================================================================================"
    echo ""
    echo "✅ 모든 노드에서 Munge가 정상 작동합니다."
    echo ""
    if [ "$USE_SSHPASS" = true ]; then
        echo "💡 권장: SSH 키를 설정하면 다음부터 비밀번호 입력이 불필요합니다:"
        echo "   ./setup_ssh_passwordless.sh"
        echo ""
    fi
    echo "다음 단계:"
    echo "  1. Slurm 설치 계속 진행"
    echo "  2. 또는: ./setup_cluster_full.sh"
else
    echo "⚠️  일부 노드에서 Munge 설정 실패"
    echo "================================================================================"
    echo ""
    echo "수동 확인이 필요합니다:"
    echo "  1. 각 노드에서: systemctl status munge"
    echo "  2. 각 노드에서: munge -n | unmunge"
    echo "  3. 로그 확인: journalctl -u munge -n 50"
fi

echo ""
