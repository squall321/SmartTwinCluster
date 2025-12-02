#!/bin/bash

echo "=========================================="
echo "🔧 slurmd systemd 서비스 영구 수정"
echo "=========================================="
echo ""

NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

for NODE in "${NODES[@]}"; do
    echo "📝 $NODE: slurmd.service 수정 중..."
    
    # 수정된 서비스 파일 생성
    ssh ${SSH_USER}@${NODE} "sudo tee /etc/systemd/system/slurmd.service > /dev/null" << 'EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd -D -vvv
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TimeoutStartSec=300
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # daemon-reload
    ssh ${SSH_USER}@${NODE} "sudo systemctl daemon-reload"
    
    echo "✅ $NODE: 서비스 파일 수정 완료"
    echo ""
done

echo "=========================================="
echo "✅ 모든 노드 systemd 서비스 수정 완료"
echo "=========================================="
echo ""
echo "변경 사항:"
echo "  - Type: forking → simple"
echo "  - PIDFile 제거 (불필요)"
echo "  - TimeoutStartSec: 90s → 300s"
echo "  - Restart: on-failure 추가"
echo "  - 로그 레벨: verbose (-vvv)"
echo ""
echo "이제 slurmd가 안정적으로 시작/중지됩니다."
echo ""
