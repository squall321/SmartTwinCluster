#!/bin/bash

echo "================================================================================"
echo "🔑 SSH 키 수동 복사 (빠른 해결)"
echo "================================================================================"
echo ""

# 1. SSH 키 확인
echo "📍 Step 1/3: SSH 키 확인"
echo "--------------------------------------------------------------------------------"
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
    echo "✅ SSH 키 생성 완료"
else
    echo "✅ SSH 키 존재: $HOME/.ssh/id_rsa"
fi
echo ""

# 2. root 비밀번호 입력
echo "📝 Step 2/3: root 비밀번호 입력"
echo "--------------------------------------------------------------------------------"
read -sp "node001, node002의 root 비밀번호: " ROOT_PASSWORD
echo ""
echo ""

if [ -z "$ROOT_PASSWORD" ]; then
    echo "❌ 비밀번호가 필요합니다"
    exit 1
fi

# 3. sshpass 설치 확인
if ! command -v sshpass &> /dev/null; then
    echo "sshpass 설치 중..."
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# 4. 각 노드에 SSH 키 복사
echo "📤 Step 3/3: SSH 키 복사"
echo "--------------------------------------------------------------------------------"

NODES=$(sinfo -N -h -o "%N" | sort -u)

for NODE in $NODES; do
    echo "처리 중: root@${NODE}"
    
    # SSH 키 복사
    if sshpass -p "$ROOT_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa.pub root@${NODE} 2>&1 | grep -v "WARNING"; then
        echo "  ✅ SSH 키 복사 완료"
        
        # 테스트
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 root@${NODE} "hostname" 2>/dev/null; then
            echo "  ✅ 키 인증 성공"
        else
            echo "  ⚠️  키 인증 실패"
        fi
    else
        echo "  ❌ 복사 실패"
    fi
    echo ""
done

echo "================================================================================"
echo "✅ 완료!"
echo "================================================================================"
echo ""
echo "🧪 테스트:"
echo ""
for NODE in $NODES; do
    echo "ssh root@${NODE} 'hostname'"
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes root@${NODE} "hostname" 2>/dev/null
done
echo ""
echo "📄 다음 단계:"
echo "  sudo /usr/local/slurm/sbin/slurm_reboot_node.sh node001"
echo ""
