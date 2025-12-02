#!/bin/bash
################################################################################
# SSH 키 기반 인증 자동 설정
# 한 번만 설정하면 비밀번호 입력 없이 SSH 접속 가능
################################################################################

echo "================================================================================"
echo "🔑 SSH 키 기반 인증 자동 설정"
echo "================================================================================"
echo ""
echo "💡 이 스크립트를 실행하면:"
echo "   - SSH 키 생성 (없는 경우)"
echo "   - 모든 노드에 공개키 복사"
echo "   - 이후 비밀번호 입력 없이 SSH 접속 가능"
echo ""

# YAML에서 노드 정보 읽기
if [ ! -f "my_cluster.yaml" ]; then
    echo "❌ my_cluster.yaml 파일을 찾을 수 없습니다!"
    exit 1
fi

echo "📝 my_cluster.yaml에서 노드 정보 읽는 중..."
echo ""

# Python으로 노드 목록 추출
NODES=$(python3 << 'EOFPY'
import yaml

with open('my_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)

# 모든 노드 정보 수집
nodes = []

# 컨트롤러 (필요시)
controller = config['nodes']['controller']
# nodes.append(f"{controller['ssh_user']}@{controller['ip_address']}")

# 계산 노드
for node in config['nodes']['compute_nodes']:
    ssh_user = node['ssh_user']
    ip = node['ip_address']
    hostname = node['hostname']
    print(f"{ssh_user}@{ip}#{hostname}")
EOFPY
)

if [ -z "$NODES" ]; then
    echo "❌ 노드 정보를 읽을 수 없습니다!"
    exit 1
fi

echo "📋 설정할 노드 목록:"
echo "$NODES" | while IFS='#' read -r user_ip hostname; do
    echo "  - $hostname ($user_ip)"
done
echo ""

# SSH 키 확인
SSH_KEY="$HOME/.ssh/id_rsa"

if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH 키가 없습니다. 새로 생성합니다..."
    echo ""
    read -p "SSH 키 비밀번호를 설정하시겠습니까? (비밀번호 없이 하려면 그냥 Enter) (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 비밀번호 있는 키
        ssh-keygen -t rsa -b 4096 -C "slurm-cluster-key"
    else
        # 비밀번호 없는 키 (권장)
        ssh-keygen -t rsa -b 4096 -C "slurm-cluster-key" -N ""
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ SSH 키 생성 완료: $SSH_KEY"
    else
        echo "❌ SSH 키 생성 실패!"
        exit 1
    fi
else
    echo "✅ 기존 SSH 키 사용: $SSH_KEY"
fi

echo ""
echo "================================================================================"
echo "📤 각 노드에 공개키 복사 중..."
echo "================================================================================"
echo ""
echo "⚠️  각 노드의 비밀번호를 한 번씩만 입력하면 됩니다."
echo "   이후에는 비밀번호 없이 자동으로 접속됩니다!"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_NODES=""

echo "$NODES" | while IFS='#' read -r user_ip hostname; do
    echo "----------------------------------------"
    echo "📤 $hostname ($user_ip)"
    echo "----------------------------------------"
    
    # ssh-copy-id로 공개키 복사
    ssh-copy-id -o StrictHostKeyChecking=no "$user_ip" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ $hostname: 공개키 복사 완료"
        ((SUCCESS_COUNT++))
        
        # 접속 테스트
        echo "🔍 접속 테스트 중..."
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$user_ip" "echo '   ✅ 비밀번호 없이 접속 성공!'" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            echo "   ⚠️  접속 테스트 실패. 다시 시도해보세요."
        fi
    else
        echo "❌ $hostname: 공개키 복사 실패"
        ((FAIL_COUNT++))
        FAILED_NODES="$FAILED_NODES\n  - $hostname ($user_ip)"
    fi
    
    echo ""
done

echo "================================================================================"
echo "✅ SSH 키 설정 완료!"
echo "================================================================================"
echo ""

# 결과 요약 (서브셸에서 변수가 업데이트 안되므로 다시 계산)
SUCCESS_COUNT=$(echo "$NODES" | wc -l)

echo "📊 결과 요약:"
echo "  - 설정 완료: $SUCCESS_COUNT개 노드"
echo ""

echo "🧪 테스트:"
echo "$NODES" | while IFS='#' read -r user_ip hostname; do
    echo "  ssh $user_ip 'hostname'"
done
echo ""

echo "✨ 이제 다음 명령어들이 비밀번호 없이 작동합니다:"
echo "  - ssh node001 'command'"
echo "  - scp file.txt node001:/tmp/"
echo "  - ./setup_cluster_full.sh  ← 비밀번호 입력 없이 진행!"
echo ""

echo "================================================================================"
echo ""

# 자동 테스트 제안
read -p "지금 SSH 접속 테스트를 하시겠습니까? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "🧪 SSH 접속 테스트 중..."
    echo ""
    
    echo "$NODES" | while IFS='#' read -r user_ip hostname; do
        echo -n "  $hostname ($user_ip): "
        
        # 비밀번호 없이 접속 시도
        RESULT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$user_ip" "hostname" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo "✅ $RESULT"
        else
            echo "❌ 접속 실패 (비밀번호가 필요함)"
        fi
    done
    
    echo ""
fi

echo "================================================================================"
echo "📋 다음 단계:"
echo ""
echo "  1. setup_cluster_full.sh 실행 (비밀번호 입력 없음!)"
echo "     ./setup_cluster_full.sh"
echo ""
echo "  2. 또는 개별 노드 접속 테스트"
echo "     ssh node001"
echo ""
echo "================================================================================"
