#!/bin/bash
################################################################################
# SSH + sudo 수동 설정 가이드 (단계별)
################################################################################

cat << 'EOF'
================================================================================
🔧 SSH + sudo 수동 설정 가이드
================================================================================

현재 상황:
  • node1: 192.168.122.90
  • node2: 192.168.122.103
  • SSH 키는 복사되었지만 연결 안 됨
  • sudo 권한 필요

================================================================================
해결 방법 (각 노드에서 실행)
================================================================================

1️⃣  node1 (192.168.122.90) 설정
────────────────────────────────────────

# 비밀번호로 접속
ssh koopark@192.168.122.90

# SSH 권한 수정
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
ls -la ~/.ssh/

# SELinux 문제 해결 (CentOS/RHEL인 경우)
sudo restorecon -R ~/.ssh 2>/dev/null || true

# sudo 권한 설정
sudo usermod -aG sudo koopark
echo 'koopark ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/koopark
sudo chmod 0440 /etc/sudoers.d/koopark

# 테스트
sudo whoami  # "root" 출력되어야 함

# 로그아웃
exit

# 컨트롤러에서 SSH 키 인증 테스트
ssh koopark@192.168.122.90 'hostname && sudo whoami'
# node1 출력
# root 출력

────────────────────────────────────────

2️⃣  node2 (192.168.122.103) 설정
────────────────────────────────────────

# 위와 동일하게 반복
ssh koopark@192.168.122.103

chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
sudo restorecon -R ~/.ssh 2>/dev/null || true

sudo usermod -aG sudo koopark
echo 'koopark ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/koopark
sudo chmod 0440 /etc/sudoers.d/koopark

sudo whoami
exit

ssh koopark@192.168.122.103 'hostname && sudo whoami'

================================================================================
3️⃣  최종 테스트
================================================================================

컨트롤러(smarttwincluster)에서:

# SSH 연결 테스트
ssh 192.168.122.90 'echo OK'
ssh 192.168.122.103 'echo OK'

# sudo 테스트
ssh 192.168.122.90 'sudo whoami'
ssh 192.168.122.103 'sudo whoami'

# 모두 성공하면
cd ~/claude/KooSlurmInstallAutomation
python3 test_connection.py my_multihead_cluster.yaml

================================================================================
빠른 복사 명령어 (각 노드에서 실행)
================================================================================

# node1에서:
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && sudo restorecon -R ~/.ssh 2>/dev/null && sudo usermod -aG sudo koopark && echo 'koopark ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/koopark && sudo chmod 0440 /etc/sudoers.d/koopark

# node2에서:
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && sudo restorecon -R ~/.ssh 2>/dev/null && sudo usermod -aG sudo koopark && echo 'koopark ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/koopark && sudo chmod 0440 /etc/sudoers.d/koopark

================================================================================
문제 해결
================================================================================

Q: "Permission denied (publickey,password)"
A: SSH 권한 문제
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys

Q: "sudo: a password is required"
A: sudo 권한 문제
   각 노드에서:
   su -  # root로 전환
   echo 'koopark ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/koopark
   chmod 0440 /etc/sudoers.d/koopark

Q: SELinux 관련 오류
A: sudo restorecon -R ~/.ssh
   또는
   sudo setenforce 0

================================================================================
모든 설정 완료 후
================================================================================

cd ~/claude/KooSlurmInstallAutomation
source venv/bin/activate
./setup_cluster_full.sh

================================================================================
EOF
