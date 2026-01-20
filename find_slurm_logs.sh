#!/bin/bash
# Slurm 로그 파일 위치 찾기

echo "=========================================="
echo "Slurm 로그 파일 위치 찾기"
echo "=========================================="
echo ""

# 1. slurm.conf에서 로그 경로 확인
echo "=== 1. slurm.conf에 설정된 로그 경로 ==="
if [[ -f /etc/slurm/slurm.conf ]]; then
    echo "SlurmctldLogFile:"
    grep "^SlurmctldLogFile" /etc/slurm/slurm.conf || echo "  설정 없음 (기본값: /var/log/slurm/slurmctld.log)"
    echo ""
    echo "SlurmdLogFile:"
    grep "^SlurmdLogFile" /etc/slurm/slurm.conf || echo "  설정 없음 (기본값: /var/log/slurm/slurmd.log)"
    echo ""
    echo "SlurmdbdLogFile (slurmdbd.conf):"
    if [[ -f /etc/slurm/slurmdbd.conf ]]; then
        grep "^LogFile" /etc/slurm/slurmdbd.conf || echo "  설정 없음"
    else
        echo "  slurmdbd.conf 파일 없음"
    fi
else
    echo "  /etc/slurm/slurm.conf 파일이 없습니다!"
fi
echo ""

# 2. 실제 로그 파일 찾기
echo "=== 2. 실제 로그 파일 찾기 ==="
echo "/var/log/slurm/ 디렉토리:"
if [[ -d /var/log/slurm ]]; then
    ls -lh /var/log/slurm/
else
    echo "  /var/log/slurm 디렉토리가 없습니다"
fi
echo ""

echo "/var/log/ 에서 slurm 관련 파일:"
find /var/log -name "*slurm*" -type f 2>/dev/null | head -10 || echo "  찾을 수 없음"
echo ""

# 3. journalctl로 slurmctld 로그 확인
echo "=== 3. systemd journal에서 slurmctld 로그 ==="
echo "최근 slurmctld 로그 (최근 50줄):"
journalctl -u slurmctld -n 50 --no-pager 2>/dev/null || echo "  journalctl에서 slurmctld 로그 없음"
echo ""

# 4. slurmctld 프로세스 확인
echo "=== 4. slurmctld 프로세스 ==="
ps aux | grep slurmctld | grep -v grep || echo "  slurmctld 프로세스가 실행 중이지 않습니다!"
echo ""

# 5. systemd 서비스 로그 경로
echo "=== 5. systemd 서비스 로그 ==="
echo "slurmctld 서비스 상태:"
systemctl status slurmctld --no-pager -l 2>/dev/null | head -20 || echo "  서비스 상태 확인 실패"
echo ""

# 6. Job 관련 로그 찾기
echo "=== 6. 최근 수정된 로그 파일 (최근 1시간) ==="
find /var/log -name "*.log" -mmin -60 -type f 2>/dev/null | xargs ls -lh 2>/dev/null | head -10 || echo "  없음"
echo ""

echo "=========================================="
echo "로그 확인 방법"
echo "=========================================="
echo ""
echo "1. slurmctld 로그가 파일로 있으면:"
echo "   sudo tail -100 /var/log/slurm/slurmctld.log"
echo ""
echo "2. systemd journal을 사용하면:"
echo "   journalctl -u slurmctld -n 100 --no-pager"
echo ""
echo "3. 특정 Job 검색:"
echo "   journalctl -u slurmctld --no-pager | grep -i 'job 2'"
echo ""
echo "4. 최근 에러만 보기:"
echo "   journalctl -u slurmctld -n 100 --no-pager | grep -i error"
echo ""
