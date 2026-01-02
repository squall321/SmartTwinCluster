#!/bin/bash
################################################################################
# Slurm systemd 서비스 파일 생성 (Type=simple, root 실행)
# slurmctld와 slurmd 서비스 파일을 Type=simple로 생성
#
# Type=simple 선택 이유:
#   - Slurm 23.11.10과의 호환성
#   - sd_notify() 신호 대기 불필요
#   - 더 안정적인 서비스 시작
#
# root 실행 이유:
#   - cgroup v2 리소스 관리 (CPU, 메모리, GPU)
#   - 특권 포트 바인딩 (6818)
#   - 사용자 작업을 각 UID로 격리 실행
#   - HPC 표준 권장 방식
################################################################################

set -e

echo "=========================================="
echo "📝 Slurm systemd 서비스 파일 생성"
echo "=========================================="
echo ""

################################################################################
# slurmctld.service (컨트롤러용)
################################################################################

echo "1️⃣  slurmctld.service 생성 (Type=simple)..."

sudo tee /etc/systemd/system/slurmctld.service > /dev/null << 'SLURMCTLD_EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmctld.pid
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
SLURMCTLD_EOF

echo "✅ slurmctld.service 생성 완료 (Type=simple)"
echo ""

################################################################################
# slurmd.service (계산 노드용)
################################################################################

echo "2️⃣  slurmd.service 생성 (Type=simple)..."

sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'SLURMD_EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd $SLURMD_OPTIONS
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

echo "✅ slurmd.service 생성 완료 (Type=simple)"
echo ""

################################################################################
# slurmdbd.service (데이터베이스 데몬용)
################################################################################

echo "3️⃣  slurmdbd.service 생성 (Type=simple)..."

sudo tee /etc/systemd/system/slurmdbd.service > /dev/null << 'SLURMDBD_EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target munge.service mariadb.service mysql.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurmdbd.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmdbd
ExecStartPre=/bin/sh -c 'pkill -9 slurmdbd || true'
ExecStartPre=/bin/sleep 1
ExecStart=/usr/local/slurm/sbin/slurmdbd $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmdbd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMDBD_EOF

echo "✅ slurmdbd.service 생성 완료 (Type=simple)"
echo "  - ExecStartPre: 기존 slurmdbd 프로세스 자동 정리"
echo "  - PID 파일: /run/slurm/slurmdbd.pid"
echo ""

################################################################################
# PID 디렉토리 생성
################################################################################

echo "4️⃣  PID 디렉토리 생성..."

sudo mkdir -p /run/slurm
sudo chown root:root /run/slurm
sudo chmod 755 /run/slurm

echo "✅ PID 디렉토리 생성 완료 (/run/slurm, root:root)"
echo ""

################################################################################
# systemd 리로드
################################################################################

echo "5️⃣  systemd daemon-reload..."

sudo systemctl daemon-reload

echo "✅ systemd 리로드 완료"
echo ""

################################################################################
# 완료
################################################################################

echo "=========================================="
echo "✅ systemd 서비스 파일 생성 완료!"
echo "=========================================="
echo ""
echo "생성된 파일:"
echo "  - /etc/systemd/system/slurmctld.service (Type=simple, root 실행)"
echo "  - /etc/systemd/system/slurmd.service (Type=simple, root 실행)"
echo "  - /etc/systemd/system/slurmdbd.service (Type=simple, 자동 cleanup)"
echo ""
echo "다음 단계:"
echo "  1. 컨트롤러:"
echo "     sudo systemctl enable slurmdbd slurmctld"
echo "     sudo systemctl start slurmdbd"
echo "     sudo systemctl start slurmctld"
echo ""
echo "  2. 계산 노드:"
echo "     sudo systemctl enable slurmd"
echo "     sudo systemctl start slurmd"
echo ""
