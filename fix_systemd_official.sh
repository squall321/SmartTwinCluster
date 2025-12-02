#!/bin/bash
################################################################################
# Slurm systemd 서비스를 공식 권장사항에 맞게 수정
# - slurmctld, slurmd, slurmdbd: Type=notify
# - munged: Type=forking
################################################################################

set -e

echo "=========================================="
echo "🔧 Slurm systemd 서비스 공식 권장 설정"
echo "=========================================="
echo ""
echo "권장 Type:"
echo "  - slurmctld: notify"
echo "  - slurmd: notify"
echo "  - slurmdbd: notify"
echo "  - munged: forking (기본값 유지)"
echo ""

################################################################################
# 1. 로컬 (컨트롤러) slurmctld 수정
################################################################################

echo "1️⃣  컨트롤러 slurmctld.service 수정..."
echo "----------------------------------------"

sudo tee /etc/systemd/system/slurmctld.service > /dev/null << 'EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=notify
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld -D $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ slurmctld.service 수정 완료"
echo ""

################################################################################
# 2. 로컬 slurmdbd 수정
################################################################################

echo "2️⃣  컨트롤러 slurmdbd.service 수정..."
echo "----------------------------------------"

sudo tee /etc/systemd/system/slurmdbd.service > /dev/null << 'EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service
Wants=mariadb.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurmdbd.conf

[Service]
Type=notify
EnvironmentFile=-/etc/default/slurmdbd
ExecStart=/usr/local/slurm/sbin/slurmdbd -D $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmdbd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ slurmdbd.service 수정 완료"
echo ""

################################################################################
# 3. 로컬 slurmd 수정 (컨트롤러가 compute node도 겸할 경우)
################################################################################

echo "3️⃣  컨트롤러 slurmd.service 수정..."
echo "----------------------------------------"

sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=notify
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ slurmd.service 수정 완료"
echo ""

################################################################################
# 4. 원격 노드 slurmd 수정
################################################################################

echo "4️⃣  원격 노드 slurmd.service 수정..."
echo "----------------------------------------"

COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "   📝 $node: slurmd.service 수정 중..."
    
    ssh ${SSH_USER}@${node} "sudo tee /etc/systemd/system/slurmd.service > /dev/null" << 'EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=notify
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    ssh ${SSH_USER}@${node} "sudo systemctl daemon-reload"
    echo "   ✅ $node: 수정 완료"
done

echo ""
echo "✅ 모든 원격 노드 수정 완료"
echo ""

################################################################################
# 5. 서비스 재시작
################################################################################

echo "5️⃣  서비스 재시작..."
echo "----------------------------------------"

read -p "서비스를 재시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # slurmdbd 재시작
    echo ""
    echo "   🔄 slurmdbd 재시작..."
    sudo systemctl restart slurmdbd
    sleep 3
    
    if sudo systemctl is-active --quiet slurmdbd; then
        echo "   ✅ slurmdbd 재시작 성공"
    else
        echo "   ⚠️  slurmdbd 재시작 실패"
        sudo systemctl status slurmdbd --no-pager -l
    fi
    
    # slurmctld 재시작
    echo ""
    echo "   🔄 slurmctld 재시작..."
    sudo systemctl restart slurmctld
    sleep 3
    
    if sudo systemctl is-active --quiet slurmctld; then
        echo "   ✅ slurmctld 재시작 성공"
    else
        echo "   ⚠️  slurmctld 재시작 실패"
        sudo systemctl status slurmctld --no-pager -l
    fi
    
    # 원격 노드 slurmd 재시작
    for node in "${COMPUTE_NODES[@]}"; do
        echo ""
        echo "   🔄 $node: slurmd 재시작..."
        ssh ${SSH_USER}@${node} "sudo systemctl restart slurmd"
        sleep 2
        
        if ssh ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd"; then
            echo "   ✅ $node: slurmd 재시작 성공"
        else
            echo "   ⚠️  $node: slurmd 재시작 실패"
            ssh ${SSH_USER}@${node} "sudo systemctl status slurmd --no-pager -l"
        fi
    done
    
    echo ""
    echo "⏱️  안정화 대기 중 (10초)..."
    sleep 10
    
    echo ""
    echo "✅ 모든 서비스 재시작 완료"
else
    echo "⏭️  서비스 재시작 건너뜀"
    echo ""
    echo "수동 재시작:"
    echo "  sudo systemctl restart slurmdbd"
    echo "  sudo systemctl restart slurmctld"
    echo "  ssh koopark@192.168.122.90 'sudo systemctl restart slurmd'"
    echo "  ssh koopark@192.168.122.103 'sudo systemctl restart slurmd'"
fi

echo ""

################################################################################
# 6. 상태 확인
################################################################################

echo "6️⃣  클러스터 상태 확인..."
echo "----------------------------------------"
export PATH=/usr/local/slurm/bin:$PATH

echo ""
echo "📊 노드 상태:"
sinfo || true

echo ""
echo "📋 노드 상세:"
sinfo -N -l || true

echo ""

################################################################################
# 완료
################################################################################

echo "=========================================="
echo "✅ systemd 서비스 수정 완료!"
echo "=========================================="
echo ""
echo "변경 사항:"
echo "  ✅ slurmctld: Type=notify"
echo "  ✅ slurmd: Type=notify"
echo "  ✅ slurmdbd: Type=notify"
echo "  ✅ TimeoutStartSec=120"
echo "  ✅ Restart=on-failure"
echo "  ✅ TasksMax=infinity (slurmd, slurmctld)"
echo ""
echo "이제 Slurm 공식 권장사항에 맞게 설정되었습니다."
echo ""
