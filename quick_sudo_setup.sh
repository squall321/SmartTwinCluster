#!/bin/bash
################################################################################
# sudo 권한 빠른 설정 스크립트 (IP 주소 사용)
################################################################################

echo "🔐 sudo 권한 빠른 설정"
echo "======================================"
echo ""

# my_cluster.yaml에서 사용자 이름 및 비밀번호 읽기
USER_NAME=$(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
print(config['nodes']['controller']['ssh_user'])
EOFPY
)

SSH_PASSWORD=$(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
password = config.get('cluster_info', {}).get('ssh_password', '')
print(password if password else '')
EOFPY
)

echo "사용자: $USER_NAME"
if [ -n "$SSH_PASSWORD" ] && [ "$SSH_PASSWORD" != "your_password_here" ]; then
    echo "✅ YAML에서 SSH 비밀번호 로드됨"
    USE_PASSWORD=true
    # sshpass 설치 확인
    if ! command -v sshpass &> /dev/null; then
        echo "📦 sshpass 설치 중..."
        sudo apt-get install -y sshpass > /dev/null 2>&1 || sudo yum install -y sshpass > /dev/null 2>&1
    fi
else
    echo "⚠️  SSH 키 인증 사용 (비밀번호 없음)"
    USE_PASSWORD=false
fi
echo ""

# my_cluster.yaml에서 모든 compute_nodes 읽기
mapfile -t NODES < <(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(node['ip_address'])
EOFPY
)

mapfile -t NODE_NAMES < <(python3 << 'EOFPY'
import yaml
with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(f"{node['hostname']} ({node['ip_address']})")
EOFPY
)

echo "📋 설정할 노드 (my_cluster.yaml에서 읽음):"
for i in "${!NODES[@]}"; do
  echo "  - ${NODE_NAMES[$i]}"
done
echo ""

read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "취소되었습니다."
  exit 1
fi

echo ""
echo "각 노드 설정 중..."
echo "======================================"

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  node_name="${NODE_NAMES[$i]}"
  
  echo ""
  echo "📌 $node_name 설정 중..."
  
  # 먼저 일반 사용자로 연결 시도 (sudo 권한으로 설정)
  echo "   방법 1: 현재 사용자($USER_NAME)의 sudo 권한으로 시도..."

  if [ "$USE_PASSWORD" = true ]; then
    # sshpass로 비밀번호 인증
    sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $USER_NAME@$node "
      echo '$SSH_PASSWORD' | sudo -S bash -c \"
        echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME
        chmod 0440 /etc/sudoers.d/$USER_NAME
        usermod -aG sudo $USER_NAME 2>/dev/null || usermod -aG wheel $USER_NAME 2>/dev/null
      \"
    " 2>&1 | grep -v "sudo: unable to resolve host"
  else
    # SSH 키 인증
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $USER_NAME@$node "
      # sudo를 사용해서 설정 시도
      echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$USER_NAME > /dev/null 2>&1
      sudo chmod 0440 /etc/sudoers.d/$USER_NAME 2>&1
      sudo usermod -aG sudo $USER_NAME 2>/dev/null || sudo usermod -aG wheel $USER_NAME 2>/dev/null
    " 2>&1 | grep -v "sudo: unable to resolve host"
  fi
  
  if [ $? -eq 0 ]; then
    echo "   ✅ $node: 설정 완료 (sudo 사용)"
  else
    echo "   ⚠️  방법 1 실패"
    echo ""
    echo "   방법 2: root 계정으로 시도..."
    
    # root로 연결 시도
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$node "
      usermod -aG sudo $USER_NAME 2>/dev/null || usermod -aG wheel $USER_NAME 2>/dev/null
      echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME
      chmod 0440 /etc/sudoers.d/$USER_NAME
      visudo -c -f /etc/sudoers.d/$USER_NAME
    " 2>&1
    
    if [ $? -eq 0 ]; then
      echo "   ✅ $node: 설정 완료 (root 사용)"
    else
      echo "   ❌ $node: 설정 실패"
      echo ""
      echo "   📝 수동 설정 방법:"
      echo "      ssh $USER_NAME@$node"
      echo "      su -  # 또는 sudo su -"
      echo "      usermod -aG sudo $USER_NAME"
      echo "      echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME"
      echo "      chmod 0440 /etc/sudoers.d/$USER_NAME"
    fi
  fi
done

echo ""
echo "======================================"
echo "테스트 중..."
echo "======================================"

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  node_name="${NODE_NAMES[$i]}"
  
  echo -n "  $node_name: "
  result=$(ssh -o ConnectTimeout=5 -o BatchMode=yes $USER_NAME@$node 'sudo -n whoami' 2>/dev/null)
  
  if [ "$result" = "root" ]; then
    echo "✅ sudo 권한 정상"
  else
    echo "❌ sudo 권한 없음 또는 SSH 연결 불가"
  fi
done

echo ""
echo "💡 다음 단계:"
echo "   1. SSH 연결 문제가 있다면: ./fix_ssh_quick.sh"
echo "   2. 모두 정상이면: ./setup_cluster_full.sh"
