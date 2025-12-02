#!/bin/bash

echo "=========================================="
echo "🔍 SSH 및 원격 명령 디버깅"
echo "=========================================="
echo ""

COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

# 1. SSH 키 확인
echo "1️⃣  SSH 키 확인:"
if [ -f ~/.ssh/id_rsa.pub ]; then
    echo "   ✅ SSH 키 존재: ~/.ssh/id_rsa.pub"
else
    echo "   ❌ SSH 키 없음"
fi
echo ""

# 2. 각 노드 SSH 테스트
echo "2️⃣  SSH 연결 테스트:"
for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "   $node:"
    
    # Timeout 있는 SSH 테스트
    if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${node} "echo 'SSH OK'" 2>&1 | grep -q "SSH OK"; then
        echo "      ✅ SSH 연결 성공 (키 인증)"
    else
        echo "      ❌ SSH 연결 실패 또는 비밀번호 필요"
        echo ""
        echo "      🔧 해결 방법:"
        echo "         ssh-copy-id ${SSH_USER}@${node}"
    fi
done
echo ""

# 3. 원격 systemctl 테스트
echo "3️⃣  원격 systemctl 테스트:"
for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "   $node:"
    
    # systemctl 명령 테스트 (타임아웃 10초)
    if timeout 10 ssh -o BatchMode=yes ${SSH_USER}@${node} "sudo systemctl is-active sshd" 2>/dev/null | grep -q "active"; then
        echo "      ✅ systemctl 명령 작동"
    else
        echo "      ❌ systemctl 명령 실패 또는 타임아웃"
        echo ""
        echo "      가능한 원인:"
        echo "      - sudo 비밀번호 필요"
        echo "      - systemctl이 hanging"
    fi
done
echo ""

# 4. sudoers 설정 확인
echo "4️⃣  로컬 sudoers 확인:"
if sudo grep -q "NOPASSWD" /etc/sudoers.d/slurm 2>/dev/null; then
    echo "   ✅ NOPASSWD sudoers 설정 있음"
else
    echo "   ⚠️  NOPASSWD sudoers 설정 없음"
fi
echo ""

# 5. 원격 노드 slurmd 상태 (직접 확인)
echo "5️⃣  원격 노드 slurmd 현재 상태:"
for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "   $node:"
    
    timeout 10 ssh ${SSH_USER}@${node} "sudo systemctl status slurmd --no-pager -l" 2>&1 | head -10 || echo "      타임아웃 또는 연결 실패"
done
echo ""

echo "=========================================="
echo "📋 문제 해결 방법"
echo "=========================================="
echo ""
echo "1. SSH 키 복사 (비밀번호 입력 필요):"
for node in "${COMPUTE_NODES[@]}"; do
    echo "   ssh-copy-id ${SSH_USER}@${node}"
done
echo ""
echo "2. 원격 노드에서 sudo 비밀번호 없이 실행 설정:"
echo "   각 노드에서:"
echo "   sudo visudo -f /etc/sudoers.d/koopark"
echo "   # 추가:"
echo "   koopark ALL=(ALL) NOPASSWD: /usr/bin/systemctl"
echo ""
echo "3. 수동으로 slurmd 시작 테스트:"
for node in "${COMPUTE_NODES[@]}"; do
    echo "   ssh ${SSH_USER}@${node} 'sudo systemctl start slurmd'"
done
echo ""
