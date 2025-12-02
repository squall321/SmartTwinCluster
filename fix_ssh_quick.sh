#!/bin/bash
################################################################################
# SSH 연결 빠른 수정 스크립트
################################################################################

echo "🔧 SSH 연결 빠른 수정"
echo "================================================================================"
echo ""

USER="koopark"
NODES=("192.168.122.90" "192.168.122.103")

echo "이 스크립트는 각 노드에 비밀번호로 접속하여 SSH 키 권한을 수정합니다."
echo ""
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "취소되었습니다."
    exit 1
fi

echo ""
echo "각 노드 수정 중..."
echo "────────────────────────────────────────"

for node in "${NODES[@]}"; do
    echo ""
    echo "📌 $node 처리 중..."
    
    # 비밀번호 인증으로 연결하여 권한 수정
    ssh -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        $USER@$node bash << 'ENDSSH'
        
        echo "  [1/5] .ssh 디렉토리 권한 수정..."
        chmod 700 ~/.ssh
        
        echo "  [2/5] authorized_keys 권한 수정..."
        chmod 600 ~/.ssh/authorized_keys
        
        echo "  [3/5] SELinux 컨텍스트 복원..."
        restorecon -R ~/.ssh 2>/dev/null || true
        
        echo "  [4/5] SSH 데몬 설정 확인..."
        if sudo grep -q "^PubkeyAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
            echo "      ⚠ PubkeyAuthentication이 비활성화되어 있습니다"
            echo "      수동 수정 필요: sudo vi /etc/ssh/sshd_config"
        fi
        
        echo "  [5/5] 권한 확인..."
        ls -la ~/.ssh/
        
ENDSSH
    
    if [ $? -eq 0 ]; then
        echo "  ✅ $node: 수정 완료"
    else
        echo "  ❌ $node: 수정 실패"
    fi
    
    # 키 기반 연결 테스트
    echo "  테스트 중..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 $USER@$node "echo OK" > /dev/null 2>&1; then
        echo "  ✅ SSH 키 인증 성공!"
    else
        echo "  ⚠ SSH 키 인증 실패 - 추가 조치 필요"
    fi
    
    echo ""
done

echo "================================================================================"
echo "✅ 수정 작업 완료!"
echo "================================================================================"
echo ""
echo "최종 연결 테스트:"
for node in "${NODES[@]}"; do
    echo -n "  $node: "
    if ssh -o BatchMode=yes -o ConnectTimeout=5 $USER@$node "hostname" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
done

echo ""
echo "💡 여전히 연결이 안 된다면:"
echo "   1. SSH 데몬 재시작:"
echo "      ssh $USER@192.168.122.90 'sudo systemctl restart sshd'"
echo "      ssh $USER@192.168.122.103 'sudo systemctl restart sshd'"
echo ""
echo "   2. SSH 데몬 설정 확인:"
echo "      ssh $USER@192.168.122.90"
echo "      sudo vi /etc/ssh/sshd_config"
echo "      # PubkeyAuthentication yes 확인"
echo "      # AuthorizedKeysFile .ssh/authorized_keys 확인"
echo ""
echo "   3. 상세 진단:"
echo "      ./diagnose_ssh.sh"
echo ""
