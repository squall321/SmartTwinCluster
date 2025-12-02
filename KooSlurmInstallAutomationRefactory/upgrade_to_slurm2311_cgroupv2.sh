#!/bin/bash
################################################################################
# Slurm 23.11.x + cgroup v2 완전 업그레이드 스크립트
# Slurm 22.05.8 → 23.11.10 업그레이드
################################################################################

set -e

echo "================================================================================"
echo "🚀 Slurm 23.11.x + cgroup v2 완전 업그레이드"
echo "================================================================================"
echo ""
echo "현재 상태:"
echo "  - Slurm 22.05.8 (cgroup v2 미지원)"
echo ""
echo "목표:"
echo "  - Slurm 23.11.10 (cgroup v2 완전 지원)"
echo "  - systemd 통합"
echo "  - 실제 리소스 제한 기능"
echo ""

read -p "업그레이드를 진행하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

NODES=("192.168.122.90" "192.168.122.103")
NODE_NAMES=("node001" "node002")
SSH_USER="koopark"

################################################################################
# Step 1: 기존 서비스 중지 및 백업
################################################################################

echo ""
echo "🛑 Step 1/8: 기존 서비스 중지 및 백업..."
echo "--------------------------------------------------------------------------------"

# 컨트롤러
echo "컨트롤러:"
sudo systemctl stop slurmctld 2>/dev/null || true
sudo pkill -9 slurmctld 2>/dev/null || true

# 설정 백업
BACKUP_DIR="/root/slurm_backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp -r /usr/local/slurm/etc/* "$BACKUP_DIR/" 2>/dev/null || true
echo "✅ 설정 백업: $BACKUP_DIR"

# 계산 노드들
for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "$node_name:"
    ssh ${SSH_USER}@${node_ip} "sudo systemctl stop slurmd 2>/dev/null || true; sudo pkill -9 slurmd 2>/dev/null || true" || true
    echo "✅ $node_name 서비스 중지"
done

echo ""
echo "✅ 모든 서비스 중지 완료"
echo ""

################################################################################
# Step 2: 컨트롤러에 Slurm 23.11.10 설치
################################################################################

echo "📦 Step 2/8: 컨트롤러에 Slurm 23.11.10 설치..."
echo "--------------------------------------------------------------------------------"

if [ ! -f "install_slurm_cgroup_v2.sh" ]; then
    echo "❌ install_slurm_cgroup_v2.sh를 찾을 수 없습니다!"
    exit 1
fi

chmod +x install_slurm_cgroup_v2.sh
sudo bash install_slurm_cgroup_v2.sh

if [ $? -eq 0 ]; then
    echo "✅ 컨트롤러 Slurm 23.11.10 설치 완료"
else
    echo "❌ 설치 실패"
    exit 1
fi

echo ""

################################################################################
# Step 3: 계산 노드에 Slurm 23.11.10 설치
################################################################################

echo "📦 Step 3/8: 계산 노드에 Slurm 23.11.10 설치..."
echo "--------------------------------------------------------------------------------"

for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "📦 $node_name ($node_ip) 설치 중..."
    
    # 스크립트 복사
    scp install_slurm_cgroup_v2.sh ${SSH_USER}@${node_ip}:/tmp/
    
    # 원격 설치
    ssh ${SSH_USER}@${node_ip} "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"
    
    if [ $? -eq 0 ]; then
        echo "✅ $node_name 설치 완료"
    else
        echo "❌ $node_name 설치 실패"
        exit 1
    fi
done

echo ""
echo "✅ 모든 노드에 Slurm 23.11.10 설치 완료"
echo ""

################################################################################
# Step 4: slurm.conf 생성 (Slurm 23.11.x + cgroup v2)
################################################################################

echo "📝 Step 4/8: slurm.conf 생성 (Slurm 23.11.x 버전)..."
echo "--------------------------------------------------------------------------------"

CONFIG_DIR="/usr/local/slurm/etc"

sudo tee ${CONFIG_DIR}/slurm.conf > /dev/null << 'EOFSLURM'
# slurm.conf - Slurm 23.11.10 with cgroup v2 Support
# Auto-generated for Ubuntu 22.04 + systemd

#######################################################################
# CLUSTER INFO
#######################################################################
ClusterName=mini-cluster
SlurmctldHost=smarttwincluster(192.168.122.1)

#######################################################################
# USER CONFIGURATION
#######################################################################
SlurmUser=slurm
SlurmdUser=root

#######################################################################
# PID FILES
#######################################################################
SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid

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
# Step 5: cgroup.conf 생성 (Slurm 23.11.x용)
################################################################################

echo "📝 Step 5/8: cgroup.conf 생성 (Slurm 23.11.x + cgroup v2)..."
echo "--------------------------------------------------------------------------------"

sudo tee ${CONFIG_DIR}/cgroup.conf > /dev/null << 'EOFCGROUP'
###
# Slurm cgroup v2 Configuration for Slurm 23.11.x
###

# 리소스 제한 활성화
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=no
ConstrainDevices=no

# 메모리 제한 설정
AllowedRAMSpace=100
AllowedSwapSpace=0

# Slurm 23.11.x에서 지원하는 추가 옵션들
# (23.11+에서는 이 옵션들이 자동으로 systemd cgroup v2를 사용)
EOFCGROUP

sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf
sudo chmod 644 ${CONFIG_DIR}/cgroup.conf

echo "✅ cgroup.conf 생성 완료"
echo ""

################################################################################
# Step 6: systemd 서비스 파일 생성
################################################################################

echo "📝 Step 6/8: systemd 서비스 파일 생성..."
echo "--------------------------------------------------------------------------------"

# slurmctld.service
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
PIDFile=/run/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=slurm
Group=slurm
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOFSLURMCTLD

# slurmd.service
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
PIDFile=/run/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
User=root
Group=root
TimeoutStartSec=300
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOFSLURMD

sudo systemctl daemon-reload

echo "✅ systemd 서비스 파일 생성 완료"
echo ""

################################################################################
# Step 7: 설정 파일 배포
################################################################################

echo "📤 Step 7/8: 설정 파일을 계산 노드에 배포..."
echo "--------------------------------------------------------------------------------"

for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "📦 $node_name:"
    
    # slurm.conf
    scp ${CONFIG_DIR}/slurm.conf ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/slurm.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/slurm.conf"
    
    # cgroup.conf
    scp ${CONFIG_DIR}/cgroup.conf ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/cgroup.conf ${CONFIG_DIR}/ && sudo chown slurm:slurm ${CONFIG_DIR}/cgroup.conf"
    
    # systemd 서비스
    scp /etc/systemd/system/slurmd.service ${SSH_USER}@${node_ip}:/tmp/
    ssh ${SSH_USER}@${node_ip} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload"
    
    echo "✅ $node_name 배포 완료"
done

echo ""
echo "✅ 모든 노드에 설정 배포 완료"
echo ""

################################################################################
# Step 8: 서비스 시작
################################################################################

echo "▶️  Step 8/8: Slurm 서비스 시작..."
echo "--------------------------------------------------------------------------------"

# 계산 노드 slurmd 시작
for i in "${!NODES[@]}"; do
    node_ip="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"
    
    echo ""
    echo "🚀 $node_name: slurmd 시작 중..."
    
    ssh ${SSH_USER}@${node_ip} "sudo systemctl enable slurmd && sudo systemctl start slurmd"
    
    sleep 3
    
    if ssh ${SSH_USER}@${node_ip} "sudo systemctl is-active --quiet slurmd"; then
        echo "✅ $node_name: slurmd 시작 성공"
    else
        echo "⚠️  $node_name: slurmd 시작 실패"
        ssh ${SSH_USER}@${node_ip} "sudo journalctl -u slurmd -n 10 --no-pager"
    fi
done

# 컨트롤러 slurmctld 시작
echo ""
echo "🚀 컨트롤러: slurmctld 시작 중..."

sudo systemctl enable slurmctld
sudo systemctl start slurmctld

sleep 5

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공"
else
    echo "❌ slurmctld 시작 실패"
    sudo journalctl -u slurmctld -n 20 --no-pager
    exit 1
fi

echo ""

################################################################################
# 완료 및 검증
################################################################################

echo "================================================================================"
echo "🎉 Slurm 23.11.10 + cgroup v2 업그레이드 완료!"
echo "================================================================================"
echo ""

# 버전 확인
echo "📊 버전 확인:"
/usr/local/slurm/sbin/slurmctld -V
echo ""

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

# 클러스터 상태
echo "📊 클러스터 상태:"
sinfo -N -l || true
echo ""

echo "================================================================================"
echo "📋 cgroup v2 기능 테스트"
echo "================================================================================"
echo ""
echo "1️⃣  cgroup v2 마운트 확인:"
echo "   mount | grep cgroup2"
mount | grep cgroup2 || echo "   ⚠️  cgroup2가 마운트되지 않음"
echo ""

echo "2️⃣  systemd 버전 확인 (249+ 권장):"
systemctl --version | head -1
echo ""

echo "3️⃣  Slurm이 systemd를 사용하는지 확인:"
echo "   /usr/local/slurm/sbin/slurmd -C | grep -i systemd"
/usr/local/slurm/sbin/slurmd -C 2>/dev/null | grep -i systemd || echo "   정보 없음"
echo ""

echo "4️⃣  테스트 Job 제출:"
echo "   cat > test_cgroup.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --job-name=cgroupv2_test"
echo "   #SBATCH --output=test_%j.out"
echo "   #SBATCH --cpus-per-task=1"
echo "   #SBATCH --mem=512M"
echo "   echo 'Testing cgroup v2...'"
echo "   cat /proc/self/cgroup"
echo "   EOF"
echo ""
echo "   sbatch test_cgroup.sh"
echo ""

echo "5️⃣  노드 활성화 (DOWN 상태인 경우):"
echo "   scontrol update NodeName=node001 State=RESUME"
echo "   scontrol update NodeName=node002 State=RESUME"
echo ""

echo "================================================================================"
echo "✅ 업그레이드 완료!"
echo "================================================================================"
echo ""
