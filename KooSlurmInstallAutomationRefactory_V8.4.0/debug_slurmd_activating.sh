#!/bin/bash

echo "=========================================="
echo "🔍 slurmd activating 문제 해결"
echo "=========================================="
echo ""

PROBLEM_NODE="192.168.122.90"
SSH_USER="koopark"

# 1. 원격 노드 slurmd 로그 확인
echo "1️⃣  192.168.122.90 slurmd 로그:"
echo "----------------------------------------"
ssh ${SSH_USER}@${PROBLEM_NODE} "sudo journalctl -u slurmd -n 50 --no-pager" 2>&1 | tail -30
echo ""

# 2. slurm.conf 확인 (노드 이름)
echo "2️⃣  slurm.conf 노드 설정 확인:"
echo "----------------------------------------"
echo "컨트롤러:"
grep "^NodeName" /usr/local/slurm/etc/slurm.conf 2>/dev/null || echo "slurm.conf 없음"
echo ""
echo "192.168.122.90:"
ssh ${SSH_USER}@${PROBLEM_NODE} "grep '^NodeName' /usr/local/slurm/etc/slurm.conf 2>/dev/null" || echo "slurm.conf 없음"
echo ""

# 3. 호스트명 확인
echo "3️⃣  호스트명 확인:"
echo "----------------------------------------"
echo "컨트롤러: $(hostname)"
echo "192.168.122.90: $(ssh ${SSH_USER}@${PROBLEM_NODE} 'hostname')"
echo "192.168.122.103: $(ssh ${SSH_USER}@192.168.122.103 'hostname')"
echo ""

# 4. slurmctld 상태
echo "4️⃣  slurmctld 상태:"
echo "----------------------------------------"
sudo systemctl status slurmctld --no-pager | head -15
echo ""

# 5. slurmctld 로그
echo "5️⃣  slurmctld 로그 (최근):"
echo "----------------------------------------"
sudo tail -30 /var/log/slurm/slurmctld.log 2>/dev/null || echo "로그 없음"
echo ""

echo "=========================================="
echo "📋 가능한 원인 및 해결책"
echo "=========================================="
echo ""
echo "1. 노드 이름 불일치"
echo "   → slurm.conf의 NodeName과 실제 hostname이 다름"
echo "   → 해결: slurm.conf 수정 또는 hostname 변경"
echo ""
echo "2. slurmctld가 노드 등록 거부"
echo "   → 방화벽 문제"
echo "   → 해결: 포트 6818 열기"
echo ""
echo "3. slurmd가 slurmctld를 찾지 못함"
echo "   → slurm.conf의 ControlMachine 확인"
echo "   → 해결: ControlMachine 설정 확인"
echo ""
echo "🔧 빠른 해결책:"
echo ""
echo "1. slurmd 재시작 (강제):"
echo "   ssh ${SSH_USER}@${PROBLEM_NODE} 'sudo systemctl stop slurmd'"
echo "   ssh ${SSH_USER}@${PROBLEM_NODE} 'sudo systemctl start slurmd'"
echo ""
echo "2. 노드 상태 확인:"
echo "   sinfo"
echo "   scontrol show node node001"
echo ""
echo "3. 노드가 DOWN이면 활성화:"
echo "   scontrol update NodeName=node001 State=RESUME"
echo ""
