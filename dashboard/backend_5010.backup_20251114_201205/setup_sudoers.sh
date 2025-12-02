#!/bin/bash

echo "================================================================================"
echo "🔒 노드 sudoers 설정 (비밀번호 없이 재부팅)"
echo "================================================================================"
echo ""

NODE_USER=${1:-koopark}
NODES=$(sinfo -N -h -o "%N" | sort -u)

echo "설정 대상:"
echo "  사용자: $NODE_USER"
echo "  노드: $NODES"
echo ""

read -sp "${NODE_USER}의 sudo 비밀번호: " SUDO_PASSWORD
echo ""
echo ""

for NODE in $NODES; do
    echo "================================================================================"
    echo "노드: $NODE"
    echo "================================================================================"
    
    # 1. 현재 sudo 권한 확인
    echo -n "현재 sudo 권한 (비밀번호 없이): "
    if ssh koopark@${NODE} "sudo -n /bin/true" 2>/dev/null; then
        echo "✅ 이미 설정됨"
        continue
    else
        echo "❌ 설정 필요"
    fi
    
    # 2. sudoers 설정
    echo "sudoers 설정 중..."
    
    # SSH로 명령 실행 (sudo 비밀번호 필요)
    ssh koopark@${NODE} << EOF
echo "$SUDO_PASSWORD" | sudo -S tee /etc/sudoers.d/${NODE_USER}-reboot > /dev/null << 'SUDOERS'
# Allow ${NODE_USER} to reboot without password
${NODE_USER} ALL=(ALL) NOPASSWD: /sbin/reboot
SUDOERS

echo "$SUDO_PASSWORD" | sudo -S chmod 0440 /etc/sudoers.d/${NODE_USER}-reboot
echo "$SUDO_PASSWORD" | sudo -S visudo -c
EOF
    
    # 3. 확인
    echo -n "설정 확인: "
    if ssh koopark@${NODE} "sudo -n /bin/true" 2>/dev/null; then
        echo "✅ 성공"
    else
        echo "❌ 실패"
    fi
    
    echo ""
done

echo "================================================================================"
echo "✅ 완료!"
echo "================================================================================"
echo ""
echo "🧪 테스트:"
for NODE in $NODES; do
    echo "ssh ${NODE_USER}@${NODE} 'sudo /sbin/reboot'"
done
echo ""
