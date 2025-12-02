#!/bin/bash
################################################################################
# Step 7.5 추가: 원격 노드에 systemd 서비스 파일 배포
# setup_cluster_full.sh의 Step 7 이후에 삽입할 코드
################################################################################

cat << 'EOF'

################################################################################
# Step 7.5: 원격 노드 systemd 서비스 파일 배포
################################################################################

echo "📤 Step 7.5/14: 원격 노드 systemd 서비스 파일 배포..."
echo "--------------------------------------------------------------------------------"

read -p "원격 노드에 systemd 서비스 파일을 배포하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    for node in "${COMPUTE_NODES[@]}"; do
        echo ""
        echo "📤 $node: systemd 서비스 파일 복사 중..."
        
        # slurmd.service 복사
        if [ -f "/etc/systemd/system/slurmd.service" ]; then
            scp /etc/systemd/system/slurmd.service ${SSH_USER}@${node}:/tmp/
            ssh ${SSH_USER}@${node} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload"
            echo "✅ $node: slurmd.service 배포 완료"
        else
            echo "⚠️  $node: slurmd.service 파일이 없습니다"
        fi
    done
    
    echo ""
    echo "✅ 모든 노드에 systemd 서비스 파일 배포 완료"
else
    echo "⏭️  systemd 서비스 파일 배포 건너뜀"
fi

echo ""

EOF
