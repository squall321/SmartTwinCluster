#!/bin/bash
################################################################################
# cgroup v2 Slurm 설정 파일 생성 스크립트
# Slurm 23.11.x + cgroup v2 완전 지원
################################################################################

set -e

CONFIG_DIR="/usr/local/slurm/etc"
CONTROLLER_HOST="smarttwincluster"
CONTROLLER_IP="192.168.122.1"
CLUSTER_NAME="mini-cluster"

echo "================================================================================"
echo "🔧 Slurm 23.11.x with cgroup v2 Configuration"
echo "================================================================================"
echo ""

# Slurm 버전 확인
if [ -f /usr/local/slurm/sbin/slurmctld ]; then
    SLURM_VERSION=$(/usr/local/slurm/sbin/slurmctld -V | awk '{print $2}')
    echo "감지된 Slurm 버전: $SLURM_VERSION"
    
    if [[ "$SLURM_VERSION" < "23.11" ]]; then
        echo ""
        echo "⚠️  경고: Slurm $SLURM_VERSION는 cgroup v2를 완전히 지원하지 않습니다!"
        echo "   Slurm 23.11.x 이상이 필요합니다."
        echo ""
        read -p "계속하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "취소되었습니다."
            echo ""
            echo "💡 Slurm 23.11.x로 업그레이드하려면:"
            echo "   ./upgrade_to_slurm2311_cgroupv2.sh"
            exit 0
        fi
    else
        echo "✅ Slurm 23.11.x 확인됨 - cgroup v2 완전 지원"
    fi
else
    echo "⚠️  Slurm이 설치되지 않았습니다."
    echo "   먼저 Slurm 23.11.x를 설치하세요: ./install_slurm_cgroup_v2.sh"
    exit 1
fi

echo ""

################################################################################
# Step 1: slurm.conf 생성 (Slurm 23.11.x + cgroup v2)
################################################################################

echo "📝 Step 1/4: slurm.conf 생성 (Slurm 23.11.x 버전)..."
echo "--------------------------------------------------------------------------------"

sudo tee ${CONFIG_DIR}/slurm.conf > /dev/null << 'EOFSLURM'
# slurm.conf - Slurm 23.11.x with cgroup v2 Support
# Auto-generated for Ubuntu 22.04 + systemd + cgroup v2

#######################################################################
# CLUSTER INFO
#######################################################################
ClusterName=mini-cluster
SlurmctldHost=smarttwincluster(192.168.122.1)

#######################################################################
# USER CONFIGURATION - CRITICAL!
#######################################################################
SlurmUser=slurm
SlurmdUser=root

#######################################################################
# PID FILES
#######################################################################
SlurmctldPidFile=/run/slurm/slurmctld.pid
SlurmdPidFile=/run/slurm/slurmd.pid

#######################################################################
# AUTHENTICATION
#######################################################################
AuthType=auth/munge
CredType=cred/munge

#######################################################################
# SCHEDULER
#######################################################################
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

#######################################################################
# LOGGING
#######################################################################
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log

#######################################################################
# STATE PRESERVATION
#######################################################################
StateSaveLocation=/var/spool/slurm/state
SlurmdSpoolDir=/var/spool/slurm/d

#######################################################################
# TIMEOUTS
#######################################################################
SlurmctldTimeout=300
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0

#######################################################################
# PROCESS TRACKING - cgroup v2!
#######################################################################
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity

#######################################################################
# ACCOUNTING - cgroup v2!
#######################################################################
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/cgroup
JobAcctGatherFrequency=30

#######################################################################
# COMPUTE NODES
# my_cluster.yaml 기준
#######################################################################
NodeName=node001 NodeAddr=192.168.122.90 CPUs=2 Sockets=1 CoresPerSocket=2 ThreadsPerCore=1 RealMemory=4096 State=UNKNOWN
NodeName=node002 NodeAddr=192.168.122.103 CPUs=2 Sockets=1 CoresPerSocket=2 ThreadsPerCore=1 RealMemory=4096 State=UNKNOWN

#######################################################################
# PARTITIONS
#######################################################################
PartitionName=normal Nodes=node[001-002] Default=YES MaxTime=7-00:00:00 State=UP
EOFSLURM

sudo chown slurm:slurm ${CONFIG_DIR}/slurm.conf
sudo chmod 644 ${CONFIG_DIR}/slurm.conf

echo "✅ slurm.conf 생성 완료"
echo ""

################################################################################
# Step 2: cgroup.conf 생성 (Slurm 23.11.x용)
################################################################################

echo "📝 Step 2/4: cgroup.conf 생성 (Slurm 23.11.x + cgroup v2)..."
echo "--------------------------------------------------------------------------------"

sudo tee ${CONFIG_DIR}/cgroup.conf > /dev/null << 'EOFCGROUP'
###
# Slurm cgroup v2 Configuration for Slurm 23.11.x
# systemd가 cgroup v2를 자동으로 관리
###

# 리소스 제한 활성화
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
ConstrainDevices=no

# 메모리 제한 설정
AllowedRAMSpace=100
AllowedSwapSpace=0

# Slurm 23.11.x는 systemd와 통합되어
# cgroup v2를 자동으로 사용합니다.
# 추가 옵션이 필요하지 않습니다.
EOFCGROUP

sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf
sudo chmod 644 ${CONFIG_DIR}/cgroup.conf

echo "✅ cgroup.conf 생성 완료"
echo ""

################################################################################
# Step 3: systemd 서비스 파일 생성
################################################################################

echo "📝 Step 3/4: systemd 서비스 파일 생성..."
echo "--------------------------------------------------------------------------------"

# slurmctld.service (컨트롤러용)
sudo tee /etc/systemd/system/slurmctld.service > /dev/null << 'EOFSLURMCTLD'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=slurm
Group=slurm
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOFSLURMCTLD

# slurmd.service (계산노드용)
sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'EOFSLURMD'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=root
Group=root
RuntimeDirectory=slurm
RuntimeDirectoryMode=0755
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOFSLURMD

# tmpfiles.d 설정 (런타임 디렉토리 자동 생성)
sudo tee /etc/tmpfiles.d/slurm.conf > /dev/null <<'EOFTMP'
# Slurm runtime directories
d /run/slurm 0755 slurm slurm -
EOFTMP

sudo systemd-tmpfiles --create

sudo systemctl daemon-reload

echo "✅ systemd 서비스 파일 생성 완료"
echo "✅ tmpfiles.d 설정 완료"
echo ""

################################################################################
# Step 4: 디렉토리 및 권한 설정
################################################################################

echo "📁 Step 4/4: 디렉토리 및 권한 설정..."
echo "--------------------------------------------------------------------------------"

sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/d
sudo mkdir -p /var/log/slurm
sudo mkdir -p /run/slurm

sudo chown -R slurm:slurm /var/spool/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /run/slurm

sudo chmod 755 /var/spool/slurm
sudo chmod 755 /var/spool/slurm/state
sudo chmod 755 /var/spool/slurm/d
sudo chmod 755 /var/log/slurm
sudo chmod 755 /run/slurm

# PID 파일 정리
sudo rm -f /run/slurmctld.pid
sudo rm -f /run/slurmd.pid

echo "✅ 디렉토리 및 권한 설정 완료"
echo ""

################################################################################
# cgroup v2 환경 확인
################################################################################

echo "🔍 cgroup v2 환경 확인..."
echo "--------------------------------------------------------------------------------"

# cgroup v2 마운트 확인
if mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
    echo "✅ cgroup v2가 마운트되어 있습니다"
    mount | grep cgroup2
else
    echo "⚠️  cgroup v2가 감지되지 않았습니다"
    echo "   시스템이 cgroup v1을 사용 중일 수 있습니다"
    echo ""
    echo "   cgroup v2로 전환하려면:"
    echo "   1. /etc/default/grub 수정"
    echo "      GRUB_CMDLINE_LINUX=\"systemd.unified_cgroup_hierarchy=1\""
    echo "   2. sudo update-grub"
    echo "   3. sudo reboot"
fi

# systemd 버전 확인
echo ""
echo "systemd 버전:"
systemctl --version | head -1

echo ""

################################################################################
# 완료 메시지
################################################################################

echo "================================================================================"
echo "🎉 Slurm 23.11.x + cgroup v2 설정 완료!"
echo "================================================================================"
echo ""

echo "📁 생성된 파일:"
echo "  ${CONFIG_DIR}/slurm.conf"
echo "  ${CONFIG_DIR}/cgroup.conf"
echo "  /etc/systemd/system/slurmctld.service"
echo "  /etc/systemd/system/slurmd.service"
echo ""

echo "🔧 주요 설정:"
echo "  ✅ SlurmUser=slurm"
echo "  ✅ SlurmdUser=root"
echo "  ✅ PidFile=/run/*.pid"
echo "  ✅ ProctrackType=proctrack/cgroup"
echo "  ✅ TaskPlugin=task/cgroup,task/affinity"
echo "  ✅ JobAcctGatherType=jobacct_gather/cgroup"
echo ""

echo "📋 설정 확인:"
grep -E "^SlurmUser|^SlurmdUser|PidFile|ProctrackType|TaskPlugin" ${CONFIG_DIR}/slurm.conf
echo ""

echo "📋 다음 단계:"
echo "  1. 모든 계산 노드에 설정 파일 복사"
echo "     scp ${CONFIG_DIR}/slurm.conf koopark@192.168.122.90:/tmp/"
echo "     scp ${CONFIG_DIR}/cgroup.conf koopark@192.168.122.90:/tmp/"
echo "     ssh koopark@192.168.122.90 'sudo mv /tmp/*.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/*.conf'"
echo ""
echo "  2. 서비스 시작"
echo "     sudo systemctl start slurmctld    # 컨트롤러"
echo "     ssh node001 'sudo systemctl start slurmd'  # 계산 노드"
echo ""
echo "  3. 상태 확인"
echo "     sudo systemctl status slurmctld"
echo "     /usr/local/slurm/bin/sinfo"
echo ""
echo "  4. cgroup v2 작동 확인"
echo "     cat /sys/fs/cgroup/system.slice/slurmctld.service/cgroup.controllers"
echo ""
echo "================================================================================"
