#!/bin/bash
################################################################################
# slurmctld 실시간 디버깅 스크립트
# 여러 터미널에서 동시에 로그를 확인하여 문제를 진단합니다
################################################################################

echo "========================================"
echo "🔍 slurmctld 실시간 디버깅"
echo "========================================"
echo ""

echo "이 스크립트는 slurmctld를 디버그 모드로 실행합니다."
echo "실시간으로 어떤 문제가 발생하는지 볼 수 있습니다."
echo ""

# 기존 프로세스 정리
echo "1️⃣  기존 slurmctld 프로세스 정리..."
sudo systemctl stop slurmctld 2>/dev/null || true
sudo pkill -9 slurmctld 2>/dev/null || true
sleep 2
echo "✅ 정리 완료"
echo ""

# PID 파일 정리
echo "2️⃣  PID 파일 정리..."
sudo rm -f /run/slurmctld.pid
sudo rm -f /var/run/slurmctld.pid
sudo rm -f /var/spool/slurm/state/slurmctld.pid
echo "✅ PID 파일 정리 완료"
echo ""

# 설정 파일 확인
echo "3️⃣  설정 파일 핵심 항목 확인..."
echo "----------------------------------------"
if [ -f /usr/local/slurm/etc/slurm.conf ]; then
    echo "📄 /usr/local/slurm/etc/slurm.conf:"
    grep -E "^ClusterName|^SlurmctldHost|^SlurmUser|^SlurmdUser|^SlurmctldPidFile|^StateSaveLocation|^NodeName|^PartitionName" /usr/local/slurm/etc/slurm.conf
else
    echo "❌ slurm.conf를 찾을 수 없습니다!"
    exit 1
fi
echo ""

# Munge 확인
echo "4️⃣  Munge 서비스 확인..."
if systemctl is-active --quiet munge; then
    echo "✅ Munge 정상 작동 중"
else
    echo "❌ Munge가 실행되지 않았습니다!"
    echo "Munge를 먼저 시작하세요: sudo systemctl start munge"
    exit 1
fi
echo ""

# 디렉토리 권한 확인
echo "5️⃣  중요 디렉토리 권한 확인..."
echo "----------------------------------------"
ls -ld /var/spool/slurm/state 2>/dev/null || echo "❌ /var/spool/slurm/state 없음"
ls -ld /var/log/slurm 2>/dev/null || echo "❌ /var/log/slurm 없음"
ls -ld /run/slurm 2>/dev/null || echo "❌ /run/slurm 없음"
echo ""

echo "========================================"
echo "🚀 디버그 모드로 slurmctld 시작"
echo "========================================"
echo ""
echo "⚠️  주의: 이 명령은 포어그라운드에서 실행됩니다."
echo "   Ctrl+C로 종료할 수 있습니다."
echo ""
echo "📋 확인할 내용:"
echo "  - 어떤 설정에서 멈추는가?"
echo "  - 어떤 에러 메시지가 나오는가?"
echo "  - 'fatal', 'error', 'waiting' 등의 키워드"
echo ""

read -p "디버그 모드로 시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
echo "========================================" 
echo "🔍 slurmctld 디버그 출력 시작"
echo "========================================"
echo ""

# 디버그 모드로 실행 (최대 상세 로그)
sudo -u slurm /usr/local/slurm/sbin/slurmctld -D -vvvvv

# 이 지점은 Ctrl+C로 종료했을 때만 도달
echo ""
echo "========================================"
echo "디버그 모드가 종료되었습니다."
echo "========================================"
