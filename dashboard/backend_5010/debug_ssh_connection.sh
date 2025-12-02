#!/bin/bash

echo "================================================================================"
echo "🔍 SSH 연결 디버깅"
echo "================================================================================"
echo ""

NODE_USER=${1:-koopark}
NODES=$(sinfo -N -h -o "%N" | sort -u)

echo "테스트 대상:"
echo "  사용자: $NODE_USER"
echo "  노드: $NODES"
echo ""

read -sp "${NODE_USER}의 비밀번호: " NODE_PASSWORD
echo ""
echo ""

for NODE in $NODES; do
    echo "================================================================================"
    echo "노드: $NODE"
    echo "================================================================================"
    
    # 1. Ping 테스트
    echo -n "1. Ping 테스트: "
    if ping -c 1 -W 2 $NODE >/dev/null 2>&1; then
        echo "✅"
    else
        echo "❌ - 네트워크 연결 불가"
        continue
    fi
    
    # 2. SSH 포트 확인
    echo -n "2. SSH 포트 (22) 확인: "
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/$NODE/22" 2>/dev/null; then
        echo "✅"
    else
        echo "❌ - SSH 서비스 미실행 또는 방화벽 차단"
        continue
    fi
    
    # 3. 비밀번호 인증 테스트
    echo -n "3. 비밀번호 인증 테스트: "
    if sshpass -p "$NODE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PreferredAuthentications=password ${NODE_USER}@${NODE} "echo OK" 2>/dev/null | grep -q "OK"; then
        echo "✅"
    else
        echo "❌ - 비밀번호 오류 또는 계정 없음"
        echo ""
        echo "   비밀번호를 다시 확인하세요"
        continue
    fi
    
    # 4. SSH 키 복사 시도 (상세 로그)
    echo "4. SSH 키 복사 시도:"
    sshpass -p "$NODE_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa.pub ${NODE_USER}@${NODE} 2>&1 | head -20
    
    # 5. 키 인증 테스트
    echo -n "5. 키 인증 테스트: "
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 ${NODE_USER}@${NODE} "echo OK" 2>/dev/null | grep -q "OK"; then
        echo "✅ SSH 키 인증 성공!"
    else
        echo "❌ SSH 키 인증 실패"
    fi
    
    echo ""
done

echo "================================================================================"
echo "📝 요약"
echo "================================================================================"
echo ""
echo "문제 해결 방법:"
echo ""
echo "1. 네트워크 문제:"
echo "   ping node001"
echo ""
echo "2. SSH 서비스 문제:"
echo "   ssh koopark@node001  # 수동 접속 테스트"
echo ""
echo "3. 계정 문제:"
echo "   - node에 koopark 계정이 존재하는지 확인"
echo "   - 비밀번호가 올바른지 확인"
echo ""
echo "4. 수동으로 SSH 키 복사:"
echo "   ssh-copy-id koopark@node001"
echo "   (비밀번호 입력)"
echo ""
