#!/bin/bash
################################################################################
# cgroup v2 Slurm 설정 파일 생성 스크립트 - FIXED VERSION
# Slurm 23.11.x + cgroup v2 완전 지원
# 수정사항:
#  - SlurmUser/SlurmdUser 추가
#  - PidFile 경로 수정
#  - 노드 이름 수정 (node[001-002])
################################################################################

set -e

CONFIG_DIR="/usr/local/slurm/etc"
CONTROLLER_HOST="smarttwincluster"
CONTROLLER_IP="192.168.122.1"
CLUSTER_NAME="mini-cluster"

echo "================================================================================"
echo "🔧 Slurm with cgroup v2 Configuration (FIXED)"
echo "================================================================================"
echo ""

################################################################################
# Step 1: slurm.conf 생성 (cgroup v2 지원) - FIXED
################################################################################

echo "📝 Step 1/3: slurm.conf 생성 (수정 버전)..."
echo "--------------------------------------------------------------------------------"

sudo tee ${CONFIG_DIR}/slurm.conf > /dev/null << 'EOFSLURM'
# slurm.conf - Slurm 23.11.x with cgroup v2 Support
# Auto-generated for Ubuntu 22.04 + cgroup v2
# FIXED: SlurmUser, SlurmdUser, PidFile 추가

#######################################################################
# CLUSTER INFO
#######################################################################
ClusterName=mini-cluster
SlurmctldHost=smarttwincluster(192.168.122.1)

#######################################################################
# USER CONFIGURATION - CRITICAL!
#######################################################################
SlurmUser=slurm
SlurmdUser=slurm

#######################################################################
# PID FILES - FIXED!
#######################################################################
SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid

#######################################################################
# AUTHENTICATION
#######################################################################
AuthType=auth/munge
CryptoType=crypto/munge

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
# PROCESS TRACKING (cgroup v2!)
#######################################################################
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity

#######################################################################
# ACCOUNTING (cgroup v2!)
#######################################################################
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/cgroup
JobAcctGatherFrequency=30

#######################################################################
# COMPUTE NODES
# 실제 하드웨어: 2 CPUs per node
#######################################################################
NodeName=node001 NodeAddr=192.168.122.90 CPUs=2 Sockets=1 CoresPerSocket=2 ThreadsPerCore=1 RealMemory=4096 State=UNKNOWN
NodeName=node002 NodeAddr=192.168.122.103 CPUs=2 Sockets=1 CoresPerSocket=2 ThreadsPerCore=1 RealMemory=4096 State=UNKNOWN

#######################################################################
# PARTITIONS - FIXED NODE NAMES!
#######################################################################
PartitionName=normal Nodes=node[001-002] Default=YES MaxTime=7-00:00:00 State=UP
EOFSLURM

sudo chown slurm:slurm ${CONFIG_DIR}/slurm.conf
sudo chmod 644 ${CONFIG_DIR}/slurm.conf

echo "✅ slurm.conf 생성 완료"
echo ""
echo "주요 수정 사항:"
echo "  ✅ SlurmUser=slurm 추가"
echo "  ✅ SlurmdUser=slurm 추가"
echo "  ✅ PidFile 경로 수정 (/run/*.pid)"
echo "  ✅ 노드 이름 수정 (node[001-002])"
echo ""

################################################################################
# Step 2: cgroup.conf 생성 (cgroup v2 최적화)
################################################################################

echo "📝 Step 2/3: cgroup.conf 생성 (cgroup v2)..."
echo "--------------------------------------------------------------------------------"

sudo tee ${CONFIG_DIR}/cgroup.conf > /dev/null << 'EOFCGROUP'
###
# Slurm cgroup v2 Support Configuration
###

# cgroup v2 자동 마운트 (systemd가 관리)
CgroupAutomount=yes

# 리소스 제한 활성화
ConstrainCores=yes
ConstrainRAMSpace=yes

# Swap 제한 (선택적)
ConstrainSwapSpace=no

# 디바이스 제한 (선택적)
ConstrainDevices=no

# cgroup v2 메모리 제한 설정
# MemorySwappiness - swappiness 제어 (0-100)
# AllowedSwapSpace - 허용 swap 공간 비율 (0.0-1.0)
MemorySwappiness=0
AllowedSwapSpace=0

# CPU 제한 더 정밀하게
# TaskAffinity - CPU 친화성 제어
TaskAffinity=yes

# 메모리 압박 시 동작
# MemoryLimitEnforce - 메모리 제한 강제 적용
MemoryLimitEnforce=yes
EOFCGROUP

sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf
sudo chmod 644 ${CONFIG_DIR}/cgroup.conf

echo "✅ cgroup.conf 생성 완료"
echo ""

################################################################################
# Step 3: systemd 서비스 파일 수정
################################################################################

echo "📝 Step 3/3: systemd 서비스 파일 PidFile 수정..."
echo "--------------------------------------------------------------------------------"

# slurmctld.service 수정
if [ -f /etc/systemd/system/slurmctld.service ]; then
    sudo sed -i 's|PIDFile=/var/run/slurmctld.pid|PIDFile=/run/slurmctld.pid|' /etc/systemd/system/slurmctld.service
    sudo sed -i 's|PIDFile=/var/spool/slurm/state/slurmctld.pid|PIDFile=/run/slurmctld.pid|' /etc/systemd/system/slurmctld.service
    echo "✅ slurmctld.service PidFile 수정 완료"
fi

# slurmd.service 수정
if [ -f /etc/systemd/system/slurmd.service ]; then
    sudo sed -i 's|PIDFile=/var/run/slurmd.pid|PIDFile=/run/slurmd.pid|' /etc/systemd/system/slurmd.service
    sudo sed -i 's|PIDFile=/var/spool/slurm/d/slurmd.pid|PIDFile=/run/slurmd.pid|' /etc/systemd/system/slurmd.service
    echo "✅ slurmd.service PidFile 수정 완료"
fi

# systemd 리로드
sudo systemctl daemon-reload
echo "✅ systemd 데몬 리로드 완료"
echo ""

################################################################################
# Step 4: 디렉토리 확인 및 권한 설정
################################################################################

echo "📁 Step 4/4: 디렉토리 및 권한 확인..."
echo "--------------------------------------------------------------------------------"

sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/d
sudo mkdir -p /var/log/slurm
sudo mkdir -p /run/slurm

sudo chown -R slurm:slurm /var/spool/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /run/slurm

echo "✅ 디렉토리 및 권한 설정 완료"
echo ""

################################################################################
# 완료 및 검증
################################################################################

echo "================================================================================"
echo "✅ Slurm 설정 파일 생성 완료!"
echo "================================================================================"
echo ""

echo "생성된 파일:"
echo "  📄 ${CONFIG_DIR}/slurm.conf"
echo "  📄 ${CONFIG_DIR}/cgroup.conf"
echo ""

echo "주요 수정 사항:"
echo "  ✅ SlurmUser/SlurmdUser 명시적 설정"
echo "  ✅ PidFile 경로 통일 (/run/*.pid)"
echo "  ✅ 노드 이름 정확한 매칭 (node[001-002])"
echo "  ✅ systemd 서비스 파일 동기화"
echo ""

echo "설정 확인:"
echo "  grep -E '^SlurmUser|^SlurmdUser|^PidFile' ${CONFIG_DIR}/slurm.conf"
echo ""

grep -E '^SlurmUser|^SlurmdUser|PidFile' ${CONFIG_DIR}/slurm.conf || true
echo ""

echo "다음 단계:"
echo "  1. 설정 파일을 계산 노드에 배포"
echo "  2. Slurm 서비스 재시작"
echo ""
