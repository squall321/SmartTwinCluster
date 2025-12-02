#!/bin/bash
################################################################################
# 완전 자동화: Slurm 23.11.x + cgroup v2 전체 설치
# 컨트롤러 + 모든 계산 노드 자동 설치
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 설정
COMPUTE_NODES=("192.168.122.90" "192.168.122.103")
SSH_USER="koopark"

echo "================================================================================"
echo "🚀 Slurm 23.11.x + cgroup v2 완전 자동 설치"
echo "================================================================================"
echo ""
echo "📋 설치 대상:"
echo "  컨트롤러: smarttwincluster (localhost)"
echo "  계산 노드:"
for node in "${COMPUTE_NODES[@]}"; do
    echo "    - $node"
done
echo ""

read -p "계속하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

################################################################################
# Step 1: 컨트롤러에 Slurm 설치
################################################################################

echo ""
echo "================================================================================"
echo "Step 1/5: 컨트롤러에 Slurm 23.11.x 설치"
echo "================================================================================"

chmod +x install_slurm_cgroup_v2.sh
sudo bash install_slurm_cgroup_v2.sh

if [ $? -ne 0 ]; then
    echo "❌ 컨트롤러 Slurm 설치 실패"
    exit 1
fi

echo "✅ 컨트롤러 Slurm 설치 완료"

################################################################################
# Step 2: 계산 노드에 Slurm 설치
################################################################################

echo ""
echo "================================================================================"
echo "Step 2/5: 계산 노드에 Slurm 설치"
echo "================================================================================"

for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "📦 $node: Slurm 설치 중..."
    
    # 스크립트 복사
    scp install_slurm_cgroup_v2.sh ${SSH_USER}@${node}:/tmp/
    
    # 원격 실행
    ssh ${SSH_USER}@${node} "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"
    
    if [ $? -eq 0 ]; then
        echo "✅ $node: Slurm 설치 완료"
    else
        echo "❌ $node: Slurm 설치 실패"
    fi
done

echo ""
echo "✅ 모든 노드에 Slurm 설치 완료"

################################################################################
# Step 3: 설정 파일 생성 (컨트롤러)
################################################################################

echo ""
echo "================================================================================"
echo "Step 3/5: Slurm 설정 파일 생성"
echo "================================================================================"

chmod +x configure_slurm_cgroup_v2.sh
sudo bash configure_slurm_cgroup_v2.sh

if [ $? -ne 0 ]; then
    echo "❌ 설정 파일 생성 실패"
    exit 1
fi

echo "✅ 설정 파일 생성 완료"

################################################################################
# Step 4: 설정 파일 배포 (계산 노드)
################################################################################

echo ""
echo "================================================================================"
echo "Step 4/5: 설정 파일을 계산 노드에 배포"
echo "================================================================================"

for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "📤 $node: 설정 파일 복사 중..."
    
    # slurm.conf 복사
    scp /usr/local/slurm/etc/slurm.conf ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf"
    
    # cgroup.conf 복사
    scp /usr/local/slurm/etc/cgroup.conf ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/cgroup.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/cgroup.conf"
    
    # systemd 서비스 파일 복사
    scp /etc/systemd/system/slurmd.service ${SSH_USER}@${node}:/tmp/
    ssh ${SSH_USER}@${node} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload"
    
    echo "✅ $node: 설정 파일 복사 완료"
done

echo ""
echo "✅ 모든 노드에 설정 파일 배포 완료"

################################################################################
# Step 5: 서비스 시작
################################################################################

echo ""
echo "================================================================================"
echo "Step 5/5: Slurm 서비스 시작"
echo "================================================================================"

# 컨트롤러 서비스 시작
echo ""
echo "🔧 컨트롤러: slurmctld 시작 중..."
sudo systemctl enable slurmctld
sudo systemctl restart slurmctld

sleep 3

if sudo systemctl is-active --quiet slurmctld; then
    echo "✅ slurmctld 시작 성공"
else
    echo "❌ slurmctld 시작 실패"
    sudo systemctl status slurmctld
fi

# 계산 노드 서비스 시작
for node in "${COMPUTE_NODES[@]}"; do
    echo ""
    echo "🔧 $node: slurmd 시작 중..."
    
    ssh ${SSH_USER}@${node} "sudo systemctl enable slurmd && sudo systemctl restart slurmd"
    
    sleep 2
    
    if ssh ${SSH_USER}@${node} "sudo systemctl is-active --quiet slurmd"; then
        echo "✅ $node: slurmd 시작 성공"
    else
        echo "❌ $node: slurmd 시작 실패"
        ssh ${SSH_USER}@${node} "sudo systemctl status slurmd"
    fi
done

################################################################################
# 완료 및 검증
################################################################################

echo ""
echo "================================================================================"
echo "🎉 Slurm 23.11.x + cgroup v2 설치 완료!"
echo "================================================================================"
echo ""

sleep 5

echo "🔍 클러스터 상태 확인..."
echo ""

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

# sinfo 실행
if command -v sinfo &> /dev/null; then
    echo "📊 노드 상태:"
    sinfo
    echo ""
    
    echo "📋 노드 상세 정보:"
    sinfo -N
    echo ""
else
    echo "⚠️  sinfo 명령을 찾을 수 없습니다"
    echo "   PATH를 설정하세요: source /etc/profile.d/slurm.sh"
fi

echo ""
echo "================================================================================"
echo "📋 다음 단계"
echo "================================================================================"
echo ""
echo "1️⃣  노드가 DOWN 상태라면 활성화:"
echo "   /usr/local/slurm/bin/scontrol update NodeName=node001 State=RESUME"
echo "   /usr/local/slurm/bin/scontrol update NodeName=node002 State=RESUME"
echo ""
echo "2️⃣  테스트 Job 제출:"
echo "   cat > test_job.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --job-name=cgroup_test"
echo "   #SBATCH --output=test_%j.out"
echo "   #SBATCH --nodes=1"
echo "   #SBATCH --ntasks=1"
echo "   #SBATCH --cpus-per-task=2"
echo "   #SBATCH --mem=1G"
echo "   echo 'Hello from' \$(hostname)"
echo "   echo 'CPUs allocated:' \$SLURM_CPUS_PER_TASK"
echo "   echo 'Memory allocated:' \$SLURM_MEM_PER_NODE"
echo "   sleep 10"
echo "   EOF"
echo ""
echo "   /usr/local/slurm/bin/sbatch test_job.sh"
echo "   /usr/local/slurm/bin/squeue"
echo ""
echo "3️⃣  cgroup v2 작동 확인:"
echo "   # Job 실행 중에 확인"
echo "   cat /sys/fs/cgroup/system.slice/slurmstepd.scope/job_*/step_*/cgroup.procs"
echo "   cat /sys/fs/cgroup/system.slice/slurmstepd.scope/job_*/step_*/cpu.max"
echo "   cat /sys/fs/cgroup/system.slice/slurmstepd.scope/job_*/step_*/memory.max"
echo ""
echo "4️⃣  리소스 제한 테스트:"
echo "   # CPU 제한 테스트"
echo "   cat > cpu_test.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --cpus-per-task=1"
echo "   #SBATCH --mem=512M"
echo "   stress-ng --cpu 4 --timeout 10s  # 1개만 할당했지만 4개 요청"
echo "   EOF"
echo ""
echo "   # 메모리 제한 테스트"
echo "   cat > mem_test.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --mem=100M"
echo "   stress-ng --vm 1 --vm-bytes 500M --timeout 10s  # 100MB만 할당했지만 500MB 요청"
echo "   EOF"
echo ""
echo "5️⃣  Dashboard 통합:"
echo "   cd dashboard"
echo "   export MOCK_MODE=false"
echo "   python backend/app.py &"
echo "   npm run dev"
echo ""
echo "================================================================================"
echo ""
echo "💡 유용한 명령어:"
echo ""
echo "  # Slurm 상태 확인"
echo "  /usr/local/slurm/bin/sinfo"
echo "  /usr/local/slurm/bin/scontrol show nodes"
echo ""
echo "  # cgroup v2 확인"
echo "  cat /sys/fs/cgroup/cgroup.controllers"
echo "  systemd-cgls"
echo ""
echo "  # 로그 확인"
echo "  sudo tail -f /var/log/slurm/slurmctld.log"
echo "  sudo tail -f /var/log/slurm/slurmd.log"
echo ""
echo "  # 서비스 재시작"
echo "  sudo systemctl restart slurmctld"
echo "  ssh node001 'sudo systemctl restart slurmd'"
echo ""
echo "================================================================================"
