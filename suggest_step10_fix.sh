#!/bin/bash

echo "이 스크립트는 setup_cluster_full.sh의 Step 10 부분을 수정합니다"
echo "원격 노드 systemctl 명령에 타임아웃을 추가합니다"
echo ""

# Step 10 섹션 찾기
# 원격 ssh 명령에 타임아웃 추가

cat > /tmp/step10_fix.txt << 'EOF'

# 기존:
ssh ${SSH_USER}@${node} "sudo systemctl enable slurmd && sudo systemctl restart slurmd"

# 수정:
timeout 30 ssh -o ConnectTimeout=10 ${SSH_USER}@${node} "sudo systemctl enable slurmd && sudo systemctl restart slurmd"

EOF

echo "setup_cluster_full.sh의 다음 부분을 수동으로 수정하세요:"
cat /tmp/step10_fix.txt
echo ""
echo "또는 원격 노드를 수동으로 시작:"
echo "  ssh koopark@192.168.122.90 'sudo systemctl start slurmd'"
echo "  ssh koopark@192.168.122.103 'sudo systemctl start slurmd'"
