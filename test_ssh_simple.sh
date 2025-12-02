#!/bin/bash
################################################################################
# SSH 연결 간단 테스트
################################################################################

USER="koopark"
NODES=("192.168.122.90" "192.168.122.103")

echo "🧪 SSH 연결 테스트"
echo "================================================================================"
echo ""

for node in "${NODES[@]}"; do
    echo -n "📌 $node: "
    
    # SSH 키 기반 연결 시도
    if timeout 5 ssh -o BatchMode=yes \
                    -o ConnectTimeout=3 \
                    -o StrictHostKeyChecking=no \
                    $USER@$node "hostname" 2>/dev/null; then
        echo "✅ 연결 성공"
    else
        echo "❌ 연결 실패"
        
        # 비밀번호 인증 시도
        echo "   비밀번호 인증 시도 중..."
        if timeout 5 ssh -o PreferredAuthentications=password \
                        -o PubkeyAuthentication=no \
                        -o ConnectTimeout=3 \
                        $USER@$node "echo OK" > /dev/null 2>&1; then
            echo "   ℹ️  비밀번호 인증은 가능 → SSH 키 설정 문제"
        else
            echo "   ℹ️  비밀번호 인증도 실패 → 네트워크/방화벽 문제"
        fi
    fi
    echo ""
done

echo "================================================================================"
echo ""
echo "💡 해결 방법:"
echo ""
echo "1. SSH 키 권한 수정 (추천):"
echo "   chmod +x fix_ssh_quick.sh"
echo "   ./fix_ssh_quick.sh"
echo ""
echo "2. 상세 진단:"
echo "   chmod +x diagnose_ssh.sh"
echo "   ./diagnose_ssh.sh"
echo ""
echo "3. 수동 수정 (각 노드에서):"
echo "   ssh 192.168.122.90"
echo "   chmod 700 ~/.ssh"
echo "   chmod 600 ~/.ssh/authorized_keys"
echo "   exit"
echo ""
