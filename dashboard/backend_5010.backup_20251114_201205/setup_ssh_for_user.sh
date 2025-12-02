#!/bin/bash

echo "================================================================================"
echo "🔑 SSH 키 설정 (일반 계정용)"
echo "================================================================================"
echo ""

# 1. 노드 접속 계정 확인
echo "📝 Step 1/4: 접속 정보 입력"
echo "--------------------------------------------------------------------------------"
CURRENT_USER=$(whoami)
echo "현재 사용자: $CURRENT_USER"
echo ""

read -p "노드에 접속할 사용자 이름 (기본값: $CURRENT_USER): " NODE_USER
NODE_USER=${NODE_USER:-$CURRENT_USER}

echo ""
echo "✅ 설정:"
echo "   - 컨트롤러 사용자: $CURRENT_USER"
echo "   - 노드 접속 사용자: $NODE_USER"
echo ""

read -sp "${NODE_USER}@node의 비밀번호: " NODE_PASSWORD
echo ""
echo ""

if [ -z "$NODE_PASSWORD" ]; then
    echo "❌ 비밀번호가 필요합니다"
    exit 1
fi

# 2. SSH 키 확인
echo "🔑 Step 2/4: SSH 키 확인"
echo "--------------------------------------------------------------------------------"
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
    echo "✅ SSH 키 생성 완료"
else
    echo "✅ SSH 키 존재: $HOME/.ssh/id_rsa"
fi
echo ""

# 3. sshpass 설치
echo "📦 Step 3/4: sshpass 설치 확인"
echo "--------------------------------------------------------------------------------"
if ! command -v sshpass &> /dev/null; then
    echo "sshpass 설치 중..."
    sudo apt-get update && sudo apt-get install -y sshpass
    echo "✅ sshpass 설치 완료"
else
    echo "✅ sshpass 이미 설치됨"
fi
echo ""

# 4. 각 노드에 SSH 키 복사
echo "📤 Step 4/4: SSH 키 복사"
echo "--------------------------------------------------------------------------------"

NODES=$(sinfo -N -h -o "%N" | sort -u)
echo "감지된 노드:"
echo "$NODES"
echo ""

SUCCESS=0
FAIL=0

for NODE in $NODES; do
    echo "처리 중: ${NODE_USER}@${NODE}"
    
    # SSH 키 복사
    if sshpass -p "$NODE_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa.pub ${NODE_USER}@${NODE} 2>&1 | grep -q "Number of key"; then
        echo "  ✅ SSH 키 복사 완료"
        
        # 테스트: 비밀번호 없이 접속
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 ${NODE_USER}@${NODE} "hostname" 2>/dev/null; then
            echo "  ✅ 키 인증 성공"
            ((SUCCESS++))
        else
            echo "  ⚠️  키 인증 실패"
            ((FAIL++))
        fi
    else
        echo "  ❌ 복사 실패"
        ((FAIL++))
    fi
    echo ""
done

echo "================================================================================"
echo "📊 결과"
echo "================================================================================"
echo "✅ 성공: $SUCCESS개"
echo "❌ 실패: $FAIL개"
echo ""

if [ $SUCCESS -eq 0 ]; then
    echo "❌ 모든 노드 실패"
    exit 1
fi

# 5. 테스트
echo "🧪 SSH 연결 테스트"
echo "--------------------------------------------------------------------------------"
for NODE in $NODES; do
    echo -n "${NODE_USER}@${NODE}: "
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 ${NODE_USER}@${NODE} "hostname" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
done
echo ""

# 6. sudo 권한 확인
echo "🔒 sudo 권한 확인"
echo "--------------------------------------------------------------------------------"
for NODE in $NODES; do
    echo -n "${NODE_USER}@${NODE} sudo 권한: "
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${NODE_USER}@${NODE} "sudo -n /bin/true" 2>/dev/null; then
        echo "✅ (비밀번호 없이 sudo 가능)"
    else
        echo "⚠️  (sudo에 비밀번호 필요)"
        echo ""
        echo "  ${NODE} 노드에서 다음 설정이 필요합니다:"
        echo "  sudo visudo"
        echo "  # 다음 줄 추가:"
        echo "  ${NODE_USER} ALL=(ALL) NOPASSWD: /sbin/reboot"
    fi
done
echo ""

echo "================================================================================"
echo "✅ SSH 키 설정 완료!"
echo "================================================================================"
echo ""
echo "📝 설정 요약:"
echo "  - SSH 키: $HOME/.ssh/id_rsa"
echo "  - 노드 접속: ssh ${NODE_USER}@<node_name>"
echo ""
echo "🧪 테스트 명령어:"
FIRST_NODE=$(echo "$NODES" | head -1)
echo "  ssh ${NODE_USER}@${FIRST_NODE} 'hostname'"
echo "  ssh ${NODE_USER}@${FIRST_NODE} 'sudo /sbin/reboot'"
echo ""
echo "📄 다음 단계: RebootProgram 스크립트 생성"
echo "  ./create_reboot_script.sh ${NODE_USER}"
echo ""
