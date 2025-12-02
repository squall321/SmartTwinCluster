#!/bin/bash
################################################################################
# 모든 Slurm 프로세스 강제 종료 및 정리
################################################################################

echo "================================================================================"
echo "🧹 모든 Slurm 프로세스 강제 정리"
echo "================================================================================"
echo ""

# 1. 모든 Slurm 프로세스 찾기
echo "1️⃣  Slurm 프로세스 확인..."
echo ""

SLURM_PROCS=$(ps aux | grep -E "slurm[cd]|slurmdbd" | grep -v grep)

if [ -z "$SLURM_PROCS" ]; then
    echo "✅ Slurm 프로세스가 없습니다"
else
    echo "현재 실행 중인 Slurm 프로세스:"
    echo "$SLURM_PROCS"
fi

echo ""

# 2. systemd 서비스 중지
echo "2️⃣  systemd 서비스 중지..."
sudo systemctl stop slurmctld 2>/dev/null || true
sudo systemctl stop slurmd 2>/dev/null || true
sudo systemctl stop slurmdbd 2>/dev/null || true
sleep 2
echo "✅ systemd 중지 명령 완료"
echo ""

# 3. 프로세스 강제 종료
echo "3️⃣  모든 Slurm 프로세스 강제 종료..."

# slurmctld
if pgrep -f slurmctld > /dev/null; then
    echo "   slurmctld 강제 종료 중..."
    sudo pkill -9 slurmctld
fi

# slurmd
if pgrep -f slurmd > /dev/null; then
    echo "   slurmd 강제 종료 중..."
    sudo pkill -9 slurmd
fi

# slurmdbd
if pgrep -f slurmdbd > /dev/null; then
    echo "   slurmdbd 강제 종료 중..."
    sudo pkill -9 slurmdbd
fi

sleep 2
echo "✅ 강제 종료 완료"
echo ""

# 4. PID 파일 정리
echo "4️⃣  PID 파일 정리..."
sudo rm -f /var/run/slurm/*.pid 2>/dev/null || true
sudo rm -f /run/slurm/*.pid 2>/dev/null || true
echo "✅ PID 파일 정리 완료"
echo ""

# 5. 최종 확인
echo "5️⃣  최종 확인..."
echo ""

REMAINING=$(ps aux | grep -E "slurm[cd]|slurmdbd" | grep -v grep)

if [ -z "$REMAINING" ]; then
    echo "✅ 모든 Slurm 프로세스가 정리되었습니다!"
else
    echo "⚠️  일부 프로세스가 남아있습니다:"
    echo "$REMAINING"
    echo ""
    echo "💡 수동으로 제거:"
    echo "$REMAINING" | awk '{print "   sudo kill -9 "$2}'
fi

echo ""

echo "================================================================================"
echo "🎉 정리 완료!"
echo "================================================================================"
echo ""

echo "다음 단계:"
echo "1. slurmdbd 수정:"
echo "   sudo ./fix_slurmdbd_complete.sh"
echo ""
echo "2. 클러스터 시작:"
echo "   ./start_slurm_cluster.sh"
echo ""

echo "================================================================================"
