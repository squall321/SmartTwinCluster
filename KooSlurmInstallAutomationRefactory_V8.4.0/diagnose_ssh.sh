#!/bin/bash
################################################################################
# SSH 연결 문제 진단 및 해결 스크립트
################################################################################

echo "🔍 SSH 연결 문제 진단"
echo "================================================================================"
echo ""

USER="koopark"
NODES=("192.168.122.90" "192.168.122.103")

echo "1️⃣  SSH 키 권한 확인"
echo "────────────────────────────────────────"
ls -la ~/.ssh/id_rsa
ls -la ~/.ssh/id_rsa.pub
ls -la ~/.ssh/authorized_keys

if [ ! -f ~/.ssh/id_rsa ]; then
    echo "❌ SSH 개인키가 없습니다"
    exit 1
fi

# 권한 수정
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
[ -f ~/.ssh/authorized_keys ] && chmod 600 ~/.ssh/authorized_keys

echo "✅ 로컬 SSH 키 권한 수정 완료"
echo ""

echo "2️⃣  각 노드 연결 테스트"
echo "────────────────────────────────────────"

for node in "${NODES[@]}"; do
    echo ""
    echo "📌 노드: $node"
    echo "   ─────────────────────────"
    
    # Ping 테스트
    echo -n "   [1/6] Ping 테스트... "
    if ping -c 1 -W 2 $node > /dev/null 2>&1; then
        echo "✓"
    else
        echo "✗ (네트워크 연결 불가)"
        continue
    fi
    
    # SSH 포트 테스트
    echo -n "   [2/6] SSH 포트(22) 테스트... "
    if nc -z -w 2 $node 22 > /dev/null 2>&1; then
        echo "✓"
    else
        echo "✗ (포트 닫힘)"
        continue
    fi
    
    # SSH 연결 테스트 (verbose)
    echo "   [3/6] SSH 연결 시도 (상세)..."
    ssh -v -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $USER@$node "echo 'SSH OK'" 2>&1 | tail -20
    
    # 원인 진단
    echo ""
    echo "   [4/6] 문제 진단 중..."
    
    # authorized_keys 확인 (비밀번호로)
    echo "   [5/6] 원격 authorized_keys 확인..."
    echo "         (비밀번호 입력 필요할 수 있음)"
    ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $USER@$node "ls -la ~/.ssh/authorized_keys; cat ~/.ssh/authorized_keys | grep -c 'ssh-rsa'" 2>/dev/null
    
    # SSH 데몬 설정 확인
    echo "   [6/6] SSH 데몬 설정 확인..."
    ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $USER@$node "sudo grep -E '^(PubkeyAuthentication|PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config" 2>/dev/null
    
    echo ""
done

echo ""
echo "3️⃣  해결 방법"
echo "────────────────────────────────────────"
echo ""
echo "📋 가능한 원인과 해결책:"
echo ""
echo "1. authorized_keys 권한 문제"
echo "   각 노드에서:"
echo "   ssh $USER@192.168.122.90"
echo "   chmod 700 ~/.ssh"
echo "   chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "2. SELinux 문제"
echo "   각 노드에서:"
echo "   ssh $USER@192.168.122.90"
echo "   sudo restorecon -R ~/.ssh"
echo ""
echo "3. SSH 데몬 설정 문제"
echo "   각 노드에서:"
echo "   sudo vi /etc/ssh/sshd_config"
echo "   다음 확인:"
echo "   PubkeyAuthentication yes"
echo "   AuthorizedKeysFile .ssh/authorized_keys"
echo "   sudo systemctl restart sshd"
echo ""
echo "4. 방화벽 문제"
echo "   각 노드에서:"
echo "   sudo firewall-cmd --list-all"
echo "   sudo ufw status"
echo ""

echo "================================================================================"
echo ""
echo "💡 빠른 해결 시도:"
echo ""
echo "각 노드에 비밀번호로 접속해서 다음 실행:"
echo ""
echo "for node in 192.168.122.90 192.168.122.103; do"
echo "  ssh \$node 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && sudo restorecon -R ~/.ssh 2>/dev/null'"
echo "done"
echo ""
