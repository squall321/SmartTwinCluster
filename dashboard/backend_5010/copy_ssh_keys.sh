#!/bin/bash

echo "================================================================================"
echo "🔧 SSH 키 복사 및 테스트"
echo "================================================================================"
echo ""

# 1. 접속 정보 입력
echo "📝 Step 1/4: 접속 정보 입력"
echo "--------------------------------------------------------------------------------"
read -p "노드 SSH 사용자 이름 (기본값: root): " SSH_USER
SSH_USER=${SSH_USER:-root}

read -sp "${SSH_USER}의 비밀번호: " SSH_PASSWORD
echo ""
echo ""

if [ -z "$SSH_PASSWORD" ]; then
    echo "❌ 비밀번호가 필요합니다"
    exit 1
fi

echo "✅ 사용자: $SSH_USER"
echo ""

# 2. sshpass 설치 확인
echo "📦 Step 2/4: sshpass 설치 확인"
echo "--------------------------------------------------------------------------------"
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  sshpass 설치 필요"
    read -p "sshpass를 설치하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y sshpass
        echo "✅ sshpass 설치 완료"
    else
        echo "❌ sshpass 없이는 진행할 수 없습니다"
        exit 1
    fi
else
    echo "✅ sshpass 이미 설치됨"
fi
echo ""

# 3. SSH 키 생성 (현재 사용자용)
echo "🔑 Step 3/4: SSH 키 생성"
echo "--------------------------------------------------------------------------------"
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "SSH 키 생성 중..."
    ssh-keygen -t rsa -N '' -f $HOME/.ssh/id_rsa
    echo "✅ SSH 키 생성 완료: $HOME/.ssh/id_rsa"
else
    echo "✅ SSH 키 이미 존재: $HOME/.ssh/id_rsa"
fi
echo ""

# 4. 모든 노드에 SSH 키 복사
echo "📤 Step 4/4: 모든 노드에 SSH 키 복사"
echo "--------------------------------------------------------------------------------"

NODES=$(sinfo -N -h -o "%N" | sort -u)
echo "감지된 노드:"
echo "$NODES"
echo ""

SUCCESS_NODES=()
FAIL_NODES=()

for NODE in $NODES; do
    echo "처리 중: ${SSH_USER}@${NODE}"
    
    # SSH 연결 테스트
    if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${NODE} "echo 'Connection OK'" 2>/dev/null | grep -q "Connection OK"; then
        echo "  ✅ 연결 성공"
        
        # SSH 키 복사
        if sshpass -p "$SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa.pub ${SSH_USER}@${NODE} 2>/dev/null; then
            echo "  ✅ SSH 키 복사 성공"
            
            # 키 인증 테스트
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes ${SSH_USER}@${NODE} "echo 'Key Auth OK'" 2>/dev/null | grep -q "Key Auth OK"; then
                echo "  ✅ 키 인증 테스트 성공"
                SUCCESS_NODES+=("$NODE")
            else
                echo "  ⚠️  키 인증 테스트 실패"
                FAIL_NODES+=("$NODE")
            fi
        else
            echo "  ❌ SSH 키 복사 실패"
            FAIL_NODES+=("$NODE")
        fi
    else
        echo "  ❌ 연결 실패 - 비밀번호 또는 네트워크 문제"
        FAIL_NODES+=("$NODE")
    fi
    echo ""
done

echo "================================================================================"
echo "📊 결과"
echo "================================================================================"
echo ""
echo "✅ 성공: ${#SUCCESS_NODES[@]}개 노드"
for node in "${SUCCESS_NODES[@]}"; do
    echo "  - $node"
done
echo ""

if [ ${#FAIL_NODES[@]} -gt 0 ]; then
    echo "❌ 실패: ${#FAIL_NODES[@]}개 노드"
    for node in "${FAIL_NODES[@]}"; do
        echo "  - $node"
    done
    echo ""
fi

if [ ${#SUCCESS_NODES[@]} -eq 0 ]; then
    echo "❌ 모든 노드에 SSH 키 복사 실패"
    echo ""
    echo "문제 해결:"
    echo "  1. 비밀번호 확인"
    echo "  2. 네트워크 연결 확인: ping ${NODES[0]}"
    echo "  3. SSH 서비스 확인"
    exit 1
fi

# 5. 테스트
echo "================================================================================"
echo "🧪 SSH 연결 테스트"
echo "================================================================================"
echo ""

for NODE in "${SUCCESS_NODES[@]}"; do
    echo "테스트: ${SSH_USER}@${NODE}"
    
    # 키 없이 (비밀번호)
    echo -n "  비밀번호 인증: "
    if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ${SSH_USER}@${NODE} "hostname" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
    
    # 키로 (비밀번호 없이)
    echo -n "  키 인증: "
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 ${SSH_USER}@${NODE} "hostname" 2>/dev/null; then
        echo "✅"
    else
        echo "❌"
    fi
    
    # sudo 재부팅 테스트 (실제 실행 안함)
    echo -n "  sudo 권한 확인: "
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${SSH_USER}@${NODE} "sudo -n /bin/true" 2>/dev/null; then
        echo "✅ (비밀번호 없이 sudo 가능)"
    else
        echo "⚠️  (sudo에 비밀번호 필요)"
    fi
    echo ""
done

echo "================================================================================"
echo "✅ SSH 키 설정 완료!"
echo "================================================================================"
echo ""
echo "📝 요약:"
echo "  - 현재 사용자: $(whoami)"
echo "  - SSH 키 위치: $HOME/.ssh/id_rsa"
echo "  - 노드 접속: ssh ${SSH_USER}@<node_name>"
echo ""
echo "🧪 테스트 명령어:"
if [ ${#SUCCESS_NODES[@]} -gt 0 ]; then
    FIRST_SUCCESS="${SUCCESS_NODES[0]}"
    echo "  ssh ${SSH_USER}@${FIRST_SUCCESS} 'hostname'"
    echo "  ssh ${SSH_USER}@${FIRST_SUCCESS} 'sudo /sbin/reboot'"
fi
echo ""
echo "📄 다음 단계:"
echo "  1. RebootProgram 스크립트 설정"
echo "  2. slurm.conf 업데이트"
echo "  3. slurmctld 재시작"
echo ""
echo "  실행: ./create_reboot_script.sh $SSH_USER"
echo ""
