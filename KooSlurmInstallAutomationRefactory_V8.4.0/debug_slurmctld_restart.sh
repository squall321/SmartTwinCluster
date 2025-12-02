#!/bin/bash

echo "=========================================="
echo "🔍 slurmctld 재시작 디버깅"
echo "=========================================="
echo ""

# 1. slurmctld 현재 상태
echo "1️⃣  slurmctld 현재 상태:"
echo "----------------------------------------"
sudo systemctl status slurmctld --no-pager -l | head -20
echo ""

# 2. slurmctld 프로세스 확인
echo "2️⃣  slurmctld 프로세스:"
echo "----------------------------------------"
ps aux | grep slurmctld | grep -v grep
echo ""

# 3. slurmctld 로그 (실시간)
echo "3️⃣  slurmctld 로그 (최근 30줄):"
echo "----------------------------------------"
if [ -f "/var/log/slurm/slurmctld.log" ]; then
    sudo tail -30 /var/log/slurm/slurmctld.log
else
    echo "⚠️  /var/log/slurm/slurmctld.log 없음"
fi
echo ""

# 4. slurmdbd 상태
echo "4️⃣  slurmdbd 상태:"
echo "----------------------------------------"
if sudo systemctl is-active --quiet slurmdbd; then
    echo "✅ slurmdbd 실행 중"
    sudo systemctl status slurmdbd --no-pager | head -10
else
    echo "❌ slurmdbd 실행 안 됨"
fi
echo ""

# 5. slurm.conf의 Accounting 설정 확인
echo "5️⃣  slurm.conf Accounting 설정:"
echo "----------------------------------------"
grep -i "accounting" /usr/local/slurm/etc/slurm.conf 2>/dev/null || echo "Accounting 설정 없음"
echo ""

# 6. 포트 사용 확인
echo "6️⃣  포트 사용 확인:"
echo "----------------------------------------"
echo "포트 6817 (slurmctld):"
sudo ss -tulpn | grep 6817 || echo "사용 안 됨"
echo ""
echo "포트 6819 (slurmdbd):"
sudo ss -tulpn | grep 6819 || echo "사용 안 됨"
echo ""

echo "=========================================="
echo "📋 권장 조치"
echo "=========================================="
echo ""

# slurmctld가 hung 상태인지 확인
if ps aux | grep -v grep | grep slurmctld | grep -q "D"; then
    echo "⚠️  slurmctld가 uninterruptible sleep (D) 상태입니다"
    echo "   강제 종료 필요:"
    echo "   sudo pkill -9 slurmctld"
    echo "   sudo systemctl start slurmctld"
else
    echo "1. slurmctld 강제 재시작:"
    echo "   sudo systemctl stop slurmctld"
    echo "   sudo pkill -9 slurmctld  # 혹시 남은 프로세스"
    echo "   sudo systemctl start slurmctld"
    echo ""
    echo "2. 타임아웃 대기 (최대 120초):"
    echo "   현재 systemd가 시작을 기다리는 중일 수 있습니다"
    echo ""
    echo "3. 로그 실시간 모니터링:"
    echo "   sudo tail -f /var/log/slurm/slurmctld.log"
fi

echo ""
