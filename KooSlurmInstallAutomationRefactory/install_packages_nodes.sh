#!/bin/bash
################################################################################
# 계산 노드에 필수 패키지 설치
################################################################################

USER_NAME="koopark"

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
    print(node['hostname'])
EOFPY
)

echo "================================================================================"
echo "📦 계산 노드 필수 패키지 설치"
echo "================================================================================"
echo ""

# 비밀번호 입력 (선택사항)
if command -v sshpass &> /dev/null; then
    echo "SSH 키 인증이 설정되어 있으면 Enter를 누르세요."
    read -s -p "비밀번호 (없으면 Enter): " PASSWORD
    echo ""
fi

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo "📌 $node_name ($node)"
    echo "   필수 패키지 설치 중..."
    
    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $USER_NAME@$node \
            "sudo apt-get update && \
             sudo apt-get install -y build-essential bzip2 libmunge-dev libpam0g-dev libreadline-dev libssl-dev || \
             sudo yum install -y gcc make bzip2 munge-devel pam-devel readline-devel openssl-devel" 2>&1 | grep -E "(Setting up|Complete!|已安装)" || true
    else
        ssh $USER_NAME@$node \
            "sudo apt-get update && \
             sudo apt-get install -y build-essential bzip2 libmunge-dev libpam0g-dev libreadline-dev libssl-dev || \
             sudo yum install -y gcc make bzip2 munge-devel pam-devel readline-devel openssl-devel" 2>&1 | grep -E "(Setting up|Complete!|已安装)" || true
    fi
    
    echo "   ✅ 완료"
    echo ""
done

echo "================================================================================"
echo "✅ 모든 노드에 필수 패키지 설치 완료"
echo "================================================================================"
echo ""
echo "이제 다시 Slurm 설치를 진행하세요:"
echo "  ./install_slurm_binary.sh"
echo "  또는"
echo "  python3 install_slurm.py"
