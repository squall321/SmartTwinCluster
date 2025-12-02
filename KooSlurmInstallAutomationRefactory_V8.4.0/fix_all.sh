#!/bin/bash
################################################################################
# SSH + sudo 통합 설정 스크립트
# SSH 연결 문제와 sudo 권한 문제를 한 번에 해결
################################################################################

set -e

USER_NAME="koopark"
NODES=("192.168.122.90" "192.168.122.103")
NODE_NAMES=("node001" "node002")

echo "================================================================================"
echo "🔧 SSH + sudo 통합 자동 설정"
echo "================================================================================"
echo ""
echo "이 스크립트는 다음을 자동으로 처리합니다:"
echo "  1. SSH 연결 문제 해결 (권한 수정)"
echo "  2. sudo 권한 설정"
echo "  3. 연결 테스트"
echo ""
echo "대상 노드:"
for i in "${!NODES[@]}"; do
  echo "  - ${NODE_NAMES[$i]}: ${NODES[$i]}"
done
echo ""

read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "취소되었습니다."
  exit 1
fi

echo ""
echo "================================================================================"
echo "📝 비밀번호 입력"
echo "================================================================================"
echo ""
echo "노드들의 비밀번호를 입력하세요."
echo "(모든 노드의 비밀번호가 같다고 가정합니다)"
echo ""
read -s -p "비밀번호: " PASSWORD
echo ""
echo ""

if [ -z "$PASSWORD" ]; then
  echo "❌ 비밀번호가 비어있습니다."
  exit 1
fi

echo "================================================================================"
echo "1단계: SSH 연결 문제 해결"
echo "================================================================================"
echo ""

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  node_name="${NODE_NAMES[$i]}"
  
  echo "📌 $node_name ($node)"
  echo "────────────────────────────────────────"
  
  echo "  [1/3] SSH 키 권한 수정 중..."
  
  # sshpass 사용 (비밀번호로 SSH 접속)
  sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    $USER_NAME@$node bash << 'ENDSSH'
    chmod 700 ~/.ssh 2>/dev/null || true
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
    restorecon -R ~/.ssh 2>/dev/null || true
    echo "     ✓ 권한 수정 완료"
ENDSSH
  
  if [ $? -ne 0 ]; then
    echo "     ⚠️ 권한 수정 실패"
  fi
  
  echo "  [2/3] SSH 키 복사 중..."
  
  # SSH 키 다시 복사
  sshpass -p "$PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -f -i ~/.ssh/id_rsa.pub $USER_NAME@$node > /dev/null 2>&1
  
  if [ $? -eq 0 ]; then
    echo "     ✓ SSH 키 복사 완료"
  else
    echo "     ⚠️ SSH 키 복사 실패"
  fi
  
  echo "  [3/3] SSH 키 인증 테스트..."
  
  if ssh -o BatchMode=yes -o ConnectTimeout=3 $USER_NAME@$node "echo OK" > /dev/null 2>&1; then
    echo "     ✅ SSH 키 인증 성공!"
  else
    echo "     ❌ SSH 키 인증 실패"
  fi
  
  echo ""
done

echo "================================================================================"
echo "2단계: sudo 권한 설정"
echo "================================================================================"
echo ""

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  node_name="${NODE_NAMES[$i]}"
  
  echo "📌 $node_name ($node)"
  echo "────────────────────────────────────────"
  
  # SSH 키 인증으로 연결 시도
  if ssh -o BatchMode=yes -o ConnectTimeout=3 $USER_NAME@$node "echo OK" > /dev/null 2>&1; then
    echo "  SSH 키 인증 사용"
    
    ssh $USER_NAME@$node bash << ENDSSH
      # 현재 사용자의 sudo 권한으로 설정
      echo "$PASSWORD" | sudo -S bash -c "
        usermod -aG sudo $USER_NAME 2>/dev/null || usermod -aG wheel $USER_NAME 2>/dev/null
        echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME
        chmod 0440 /etc/sudoers.d/$USER_NAME
        visudo -c -f /etc/sudoers.d/$USER_NAME
      " 2>&1 | grep -v "sudo: unable"
ENDSSH
    
  else
    echo "  비밀번호 인증 사용"
    
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      $USER_NAME@$node bash << ENDSSH
      echo "$PASSWORD" | sudo -S bash -c "
        usermod -aG sudo $USER_NAME 2>/dev/null || usermod -aG wheel $USER_NAME 2>/dev/null
        echo '$USER_NAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER_NAME
        chmod 0440 /etc/sudoers.d/$USER_NAME
        visudo -c -f /etc/sudoers.d/$USER_NAME
      " 2>&1 | grep -v "sudo: unable"
ENDSSH
  fi
  
  if [ $? -eq 0 ]; then
    echo "  ✅ sudo 권한 설정 완료"
  else
    echo "  ⚠️ sudo 권한 설정 실패"
  fi
  
  echo ""
done

echo "================================================================================"
echo "3단계: 최종 테스트"
echo "================================================================================"
echo ""

all_success=true

for i in "${!NODES[@]}"; do
  node="${NODES[$i]}"
  node_name="${NODE_NAMES[$i]}"
  
  echo -n "📌 $node_name ($node): "
  
  # SSH 키 인증 테스트
  if ! ssh -o BatchMode=yes -o ConnectTimeout=3 $USER_NAME@$node "echo OK" > /dev/null 2>&1; then
    echo "❌ SSH 연결 실패"
    all_success=false
    continue
  fi
  
  # sudo 권한 테스트
  result=$(ssh -o BatchMode=yes $USER_NAME@$node 'sudo -n whoami' 2>/dev/null)
  
  if [ "$result" = "root" ]; then
    echo "✅ 모두 정상 (SSH + sudo)"
  else
    echo "⚠️ SSH 연결됨, sudo 권한 없음"
    all_success=false
  fi
done

echo ""
echo "================================================================================"

if [ "$all_success" = true ]; then
  echo "🎉 모든 설정 완료!"
  echo "================================================================================"
  echo ""
  echo "다음 단계:"
  echo "  source venv/bin/activate"
  echo "  ./setup_cluster_full.sh"
else
  echo "⚠️ 일부 노드 설정 실패"
  echo "================================================================================"
  echo ""
  echo "수동 설정이 필요합니다. 각 노드에 직접 접속하여:"
  echo ""
  echo "  ssh 192.168.122.90"
  echo "  su -  # root로 전환"
  echo "  usermod -aG sudo koopark"
  echo "  echo 'koopark ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/koopark"
  echo "  chmod 0440 /etc/sudoers.d/koopark"
fi

echo ""
