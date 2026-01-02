#!/bin/bash
################################################################################
# Compute 노드용 slurmd systemd 서비스 설정 스크립트
# - /run/slurm 디렉토리 생성
# - slurmd.service 파일 생성 (root 실행)
# - systemd daemon-reload
# - slurmd 서비스 enable
################################################################################

set -e

echo "================================================================================"
echo "🔧 Compute Node: slurmd systemd 서비스 설정"
echo "================================================================================"
echo ""

################################################################################
# 1. PID 디렉토리 생성
################################################################################

echo "📁 Step 1/4: PID 디렉토리 생성..."

sudo mkdir -p /run/slurm
sudo chown root:root /run/slurm
sudo chmod 755 /run/slurm

echo "✅ /run/slurm 생성 완료 (root:root)"
echo ""

################################################################################
# 2. Slurm 로그 및 spool 디렉토리 확인
################################################################################

echo "📁 Step 2/4: Slurm 디렉토리 확인..."

# install_slurm_cgroup_v2.sh에서 이미 생성했지만, 없으면 생성
if [ ! -d "/var/log/slurm" ]; then
    sudo mkdir -p /var/log/slurm
    sudo chown slurm:slurm /var/log/slurm
    echo "  - /var/log/slurm 생성"
fi

if [ ! -d "/var/spool/slurm/state" ]; then
    sudo mkdir -p /var/spool/slurm/{state,d}
    sudo chown -R slurm:slurm /var/spool/slurm
    echo "  - /var/spool/slurm 생성"
fi

echo "✅ Slurm 디렉토리 확인 완료"
echo ""

################################################################################
# 3. slurmd.service 파일 생성
################################################################################

echo "📝 Step 3/4: slurmd.service 생성..."

sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'SLURMD_EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmd.pid
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
SLURMD_EOF

echo "✅ slurmd.service 생성 완료"
echo "  - 실행 권한: root (User/Group 미지정)"
echo "  - PID 파일: /run/slurm/slurmd.pid"
echo ""

################################################################################
# 4. systemd 리로드 및 서비스 enable
################################################################################

echo "🔄 Step 4/4: systemd 설정 적용..."

sudo systemctl daemon-reload
sudo systemctl enable slurmd

echo "✅ slurmd 서비스 enable 완료"
echo ""

################################################################################
# 완료 메시지
################################################################################

echo "================================================================================"
echo "✅ slurmd systemd 서비스 설정 완료!"
echo "================================================================================"
echo ""
echo "설정 정보:"
echo "  - 서비스 파일: /etc/systemd/system/slurmd.service"
echo "  - PID 디렉토리: /run/slurm (root:root)"
echo "  - 실행 권한: root"
echo "  - 자동 시작: enabled"
echo ""
echo "다음 단계:"
echo "  1. slurm.conf가 /usr/local/slurm/etc/slurm.conf에 있는지 확인"
echo "  2. munge 서비스가 실행 중인지 확인"
echo "  3. slurmd 시작: sudo systemctl start slurmd"
echo "  4. 상태 확인: sudo systemctl status slurmd"
echo ""
