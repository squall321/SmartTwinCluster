#!/bin/bash

echo "=========================================="
echo "🔧 slurmd 좀비 프로세스 제거"
echo "=========================================="
echo ""

NODE="192.168.122.90"
SSH_USER="koopark"

# 1. 좀비 프로세스 확인
echo "1️⃣  좀비 slurmd 프로세스 확인:"
echo "----------------------------------------"
ssh ${SSH_USER}@${NODE} "ps aux | grep slurmd | grep -v grep"
echo ""

# 2. systemd 서비스 중지
echo "2️⃣  systemd 서비스 중지..."
ssh ${SSH_USER}@${NODE} "sudo systemctl stop slurmd"
sleep 2
echo "✅ 서비스 중지 완료"
echo ""

# 3. 남은 프로세스 강제 종료
echo "3️⃣  남은 slurmd 프로세스 강제 종료..."
ssh ${SSH_USER}@${NODE} "sudo pkill -9 slurmd"
sleep 2
echo "✅ 프로세스 종료 완료"
echo ""

# 4. 포트 확인
echo "4️⃣  포트 6818 사용 확인:"
echo "----------------------------------------"
ssh ${SSH_USER}@${NODE} "sudo netstat -tulpn | grep 6818 || echo '포트 6818 사용 없음 ✅'"
echo ""

# 5. PID 파일 정리
echo "5️⃣  PID 파일 정리..."
ssh ${SSH_USER}@${NODE} "sudo rm -f /run/slurm/slurmd.pid /var/run/slurm/slurmd.pid"
echo "✅ PID 파일 정리 완료"
echo ""

# 6. 권한 확인
echo "6️⃣  /run/slurm 디렉토리 권한 확인..."
ssh ${SSH_USER}@${NODE} "sudo mkdir -p /run/slurm && sudo chown slurm:slurm /run/slurm"
echo "✅ 권한 설정 완료"
echo ""

# 7. slurmd 재시작
echo "7️⃣  slurmd 재시작..."
ssh ${SSH_USER}@${NODE} "sudo systemctl start slurmd"

echo "⏱️  대기 중 (10초)..."
sleep 10
echo ""

# 8. 상태 확인
echo "8️⃣  slurmd 상태 확인:"
echo "----------------------------------------"
if ssh ${SSH_USER}@${NODE} "sudo systemctl is-active --quiet slurmd"; then
    echo "✅ slurmd 정상 실행 중!"
    ssh ${SSH_USER}@${NODE} "sudo systemctl status slurmd --no-pager -l | head -15"
else
    echo "❌ slurmd 시작 실패"
    ssh ${SSH_USER}@${NODE} "sudo systemctl status slurmd --no-pager -l"
    echo ""
    echo "로그 확인:"
    ssh ${SSH_USER}@${NODE} "sudo journalctl -u slurmd -n 20 --no-pager"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ 192.168.122.90 slurmd 복구 완료!"
echo "=========================================="
echo ""
