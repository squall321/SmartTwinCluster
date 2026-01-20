#!/bin/bash
# sinfo 멈춤 문제 진단 스크립트

echo "=========================================="
echo "Slurm sinfo 멈춤 문제 진단"
echo "=========================================="
echo ""

# 1. slurmctld 서비스 상태
echo "=== 1. slurmctld 서비스 상태 ==="
systemctl status slurmctld --no-pager | head -20
echo ""

# 2. slurmdbd 서비스 상태 (DB 연결 문제 확인)
echo "=== 2. slurmdbd 서비스 상태 ==="
systemctl status slurmdbd --no-pager | head -20
echo ""

# 3. MariaDB 상태 (accounting DB)
echo "=== 3. MariaDB 상태 ==="
systemctl status mariadb --no-pager | head -15
echo ""

# 4. slurmctld 로그 (최근 에러)
echo "=== 4. slurmctld 로그 (최근 50줄) ==="
if [[ -f /var/log/slurm/slurmctld.log ]]; then
    tail -50 /var/log/slurm/slurmctld.log | grep -i "error\|warning\|fatal" || echo "에러 없음"
else
    echo "/var/log/slurm/slurmctld.log 파일이 없습니다"
fi
echo ""

# 5. slurmdbd 로그 (DB 연결 에러)
echo "=== 5. slurmdbd 로그 (최근 30줄) ==="
if [[ -f /var/log/slurm/slurmdbd.log ]]; then
    tail -30 /var/log/slurm/slurmdbd.log | grep -i "error\|warning\|fatal" || echo "에러 없음"
else
    echo "/var/log/slurm/slurmdbd.log 파일이 없습니다"
fi
echo ""

# 6. sinfo with timeout
echo "=== 6. sinfo 테스트 (5초 timeout) ==="
timeout 5 sinfo 2>&1 || echo "sinfo 명령이 5초 내에 응답하지 않았습니다"
echo ""

# 7. scontrol ping
echo "=== 7. slurmctld 연결 테스트 ==="
timeout 5 scontrol ping 2>&1 || echo "scontrol ping 실패"
echo ""

# 8. 프로세스 확인
echo "=== 8. Slurm 프로세스 ==="
ps aux | grep -E "slurmctld|slurmdbd" | grep -v grep
echo ""

# 9. 포트 리스닝 확인
echo "=== 9. Slurm 포트 리스닝 확인 ==="
echo "slurmctld (6817):"
ss -tlnp | grep 6817 || echo "  포트 6817이 리스닝 중이지 않습니다"
echo "slurmdbd (6819):"
ss -tlnp | grep 6819 || echo "  포트 6819가 리스닝 중이지 않습니다"
echo ""

# 10. DB 연결 테스트
echo "=== 10. slurm_acct_db 연결 테스트 ==="
if systemctl is-active --quiet mariadb; then
    mysql -u slurm -p'slurmdbpass' -e "USE slurm_acct_db; SHOW TABLES;" 2>&1 | head -10 || echo "DB 연결 실패"
else
    echo "MariaDB가 실행 중이지 않습니다"
fi
echo ""

echo "=========================================="
echo "진단 완료"
echo "=========================================="
echo ""
echo "해결 방법:"
echo ""
echo "1. slurmdbd가 실행 중이지 않으면:"
echo "   sudo systemctl restart slurmdbd"
echo "   sudo systemctl restart slurmctld"
echo ""
echo "2. MariaDB가 멈췄으면:"
echo "   sudo systemctl restart mariadb"
echo "   sudo systemctl restart slurmdbd"
echo "   sudo systemctl restart slurmctld"
echo ""
echo "3. DB 연결 실패하면:"
echo "   # slurmdbd.conf 설정 확인"
echo "   sudo cat /etc/slurm/slurmdbd.conf | grep -E 'StorageHost|StorageUser|StoragePass'"
echo ""
echo "4. accounting 없이 실행하려면 (임시):"
echo "   # slurm.conf에서 AccountingStorageType=accounting_storage/none으로 변경"
echo "   sudo sed -i 's/AccountingStorageType=accounting_storage\\/slurmdbd/AccountingStorageType=accounting_storage\\/none/' /etc/slurm/slurm.conf"
echo "   sudo systemctl restart slurmctld"
echo ""
