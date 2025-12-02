#!/bin/bash
################################################################################
# slurmctld 멀티 로그 뷰어
# 여러 로그를 동시에 tail -f로 확인
################################################################################

echo "========================================"
echo "📋 slurmctld 멀티 로그 뷰어"
echo "========================================"
echo ""

echo "이 스크립트를 실행한 채로 다른 터미널에서 slurmctld를 시작하세요:"
echo "  sudo systemctl start slurmctld"
echo ""
echo "또는 디버그 모드로:"
echo "  sudo -u slurm /usr/local/slurm/sbin/slurmctld -D -vvv"
echo ""

read -p "로그 모니터링을 시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 0
fi

echo ""
echo "========================================" 
echo "📊 실시간 로그 모니터링 시작"
echo "========================================" 
echo ""

# 로그 파일들이 존재하는지 확인하고 생성
sudo touch /var/log/slurm/slurmctld.log 2>/dev/null || true
sudo chown slurm:slurm /var/log/slurm/slurmctld.log 2>/dev/null || true

# multitail이 있으면 사용, 없으면 기본 방법 사용
if command -v multitail &> /dev/null; then
    echo "✅ multitail로 로그 확인 중..."
    sudo multitail \
        -l "journalctl -u slurmctld -f" \
        -l "tail -f /var/log/slurm/slurmctld.log"
else
    echo "📋 journalctl 로그 (systemd):"
    echo "========================================" 
    echo ""
    
    # journalctl과 파일 로그를 번갈아 보여주기
    (
        echo "🔵 systemd journal 로그:"
        sudo journalctl -u slurmctld -f --no-pager 2>&1 | while IFS= read -r line; do
            echo "[JOURNAL] $line"
        done
    ) &
    
    (
        sleep 2
        echo ""
        echo "🟢 slurmctld.log 파일:"
        sudo tail -f /var/log/slurm/slurmctld.log 2>&1 | while IFS= read -r line; do
            echo "[LOGFILE] $line"
        done
    ) &
    
    # Ctrl+C로 종료할 때까지 대기
    wait
fi
