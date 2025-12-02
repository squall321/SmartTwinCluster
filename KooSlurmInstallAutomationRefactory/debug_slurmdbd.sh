#!/bin/bash

echo "=========================================="
echo "🔍 slurmdbd 실패 원인 분석"
echo "=========================================="
echo ""

# 1. slurmdbd 상태
echo "1️⃣  slurmdbd 서비스 상태:"
echo "----------------------------------------"
sudo systemctl status slurmdbd --no-pager -l
echo ""

# 2. slurmdbd 로그
echo "2️⃣  slurmdbd 로그 (최근 50줄):"
echo "----------------------------------------"
if [ -f "/var/log/slurm/slurmdbd.log" ]; then
    sudo tail -50 /var/log/slurm/slurmdbd.log
else
    echo "⚠️  /var/log/slurm/slurmdbd.log 파일이 없습니다"
fi
echo ""

# 3. journalctl 로그
echo "3️⃣  systemd journal 로그:"
echo "----------------------------------------"
sudo journalctl -u slurmdbd -n 50 --no-pager
echo ""

# 4. MariaDB 상태
echo "4️⃣  MariaDB 상태:"
echo "----------------------------------------"
sudo systemctl status mariadb --no-pager
echo ""

# 5. 데이터베이스 연결 테스트
echo "5️⃣  데이터베이스 연결 테스트:"
echo "----------------------------------------"
mysql -u slurm -pslurmdbpass -e "USE slurm_acct_db; SHOW TABLES;" 2>&1
echo ""

# 6. slurmdbd.conf 확인
echo "6️⃣  slurmdbd.conf 설정:"
echo "----------------------------------------"
if [ -f "/usr/local/slurm/etc/slurmdbd.conf" ]; then
    sudo cat /usr/local/slurm/etc/slurmdbd.conf | grep -v "^#" | grep -v "^$"
else
    echo "⚠️  /usr/local/slurm/etc/slurmdbd.conf 파일이 없습니다"
fi
echo ""

# 7. munge 상태
echo "7️⃣  munge 서비스 상태:"
echo "----------------------------------------"
sudo systemctl status munge --no-pager
echo ""

echo "=========================================="
echo "📋 문제 해결 가이드"
echo "=========================================="
echo ""
echo "일반적인 원인:"
echo ""
echo "1. MariaDB 연결 실패"
echo "   → sudo systemctl restart mariadb"
echo "   → mysql -u slurm -pslurmdbpass 로 연결 확인"
echo ""
echo "2. munge 인증 실패"
echo "   → sudo systemctl restart munge"
echo "   → munge -n | unmunge 테스트"
echo ""
echo "3. slurmdbd.conf 권한 문제"
echo "   → sudo chmod 600 /usr/local/slurm/etc/slurmdbd.conf"
echo "   → sudo chown slurm:slurm /usr/local/slurm/etc/slurmdbd.conf"
echo ""
echo "4. 로그 디렉토리 권한 문제"
echo "   → sudo chown -R slurm:slurm /var/log/slurm"
echo "   → sudo chown -R slurm:slurm /var/run/slurm"
echo ""
echo "5. 데이터베이스 권한 문제"
echo "   → sudo mysql"
echo "   → GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';"
echo "   → FLUSH PRIVILEGES;"
echo ""
