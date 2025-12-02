#!/bin/bash
################################################################################
# slurmctld 타임아웃 문제 진단 스크립트
################################################################################

echo "========================================"
echo "🔍 slurmctld 타임아웃 문제 진단"
echo "========================================"
echo ""

# 1. Slurm 로그 확인
echo "📋 Step 1: Slurm 로그 확인"
echo "----------------------------------------"
if [ -f /var/log/slurm/slurmctld.log ]; then
    echo "✅ slurmctld 로그 파일 존재"
    echo "마지막 30줄:"
    tail -n 30 /var/log/slurm/slurmctld.log
else
    echo "❌ /var/log/slurm/slurmctld.log 파일이 없습니다"
    echo "대체 로그 위치 확인:"
    find /var/log -name "*slurm*" -type f 2>/dev/null || echo "Slurm 로그를 찾을 수 없습니다"
fi
echo ""

# 2. systemd 서비스 상태 확인
echo "📋 Step 2: systemd 서비스 상태"
echo "----------------------------------------"
systemctl status slurmctld.service --no-pager -l
echo ""

# 3. journalctl 로그 확인
echo "📋 Step 3: systemd journal 로그 (최근 50줄)"
echo "----------------------------------------"
journalctl -u slurmctld.service -n 50 --no-pager
echo ""

# 4. Slurm 설정 파일 검증
echo "📋 Step 4: slurm.conf 검증"
echo "----------------------------------------"
if [ -f /usr/local/slurm/etc/slurm.conf ]; then
    echo "✅ slurm.conf 파일 존재"
    echo ""
    echo "주요 설정 확인:"
    grep -E "^ClusterName|^ControlMachine|^SlurmctldHost|^SlurmUser|^SlurmdUser|^StateSaveLocation|^SlurmdSpoolDir" /usr/local/slurm/etc/slurm.conf
else
    echo "❌ /usr/local/slurm/etc/slurm.conf 파일이 없습니다"
fi
echo ""

# 5. 디렉토리 권한 확인
echo "📋 Step 5: 중요 디렉토리 권한"
echo "----------------------------------------"
echo "StateSaveLocation:"
ls -ld /var/spool/slurm/state 2>/dev/null || echo "❌ /var/spool/slurm/state 디렉토리 없음"

echo ""
echo "SlurmdSpoolDir:"
ls -ld /var/spool/slurm 2>/dev/null || echo "❌ /var/spool/slurm 디렉토리 없음"

echo ""
echo "로그 디렉토리:"
ls -ld /var/log/slurm 2>/dev/null || echo "❌ /var/log/slurm 디렉토리 없음"
echo ""

# 6. Slurm 사용자 확인
echo "📋 Step 6: Slurm 사용자 확인"
echo "----------------------------------------"
id slurm 2>/dev/null && echo "✅ slurm 사용자 존재" || echo "❌ slurm 사용자 없음"
echo ""

# 7. Munge 서비스 확인
echo "📋 Step 7: Munge 서비스 상태"
echo "----------------------------------------"
systemctl status munge.service --no-pager -l
echo ""

# 8. 포트 사용 확인
echo "📋 Step 8: Slurm 포트 확인"
echo "----------------------------------------"
echo "포트 6817 (slurmctld) 사용 여부:"
netstat -tuln | grep 6817 || echo "포트 6817이 열려있지 않습니다"
echo ""

# 9. 설정 파일 구문 검사
echo "📋 Step 9: slurm.conf 구문 검사"
echo "----------------------------------------"
if command -v slurmctld &> /dev/null; then
    slurmctld -f /usr/local/slurm/etc/slurm.conf -D -vvv 2>&1 | head -n 20 &
    PID=$!
    sleep 2
    kill $PID 2>/dev/null
else
    echo "❌ slurmctld 명령어를 찾을 수 없습니다"
fi
echo ""

# 10. 일반적인 문제 체크리스트
echo "========================================"
echo "🔧 일반적인 해결 방법"
echo "========================================"
echo ""
echo "1️⃣  디렉토리 권한 수정:"
echo "   sudo mkdir -p /var/spool/slurm/state /var/log/slurm"
echo "   sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm"
echo "   sudo chmod 755 /var/spool/slurm /var/log/slurm"
echo ""
echo "2️⃣  설정 파일 권한:"
echo "   sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf"
echo "   sudo chmod 644 /usr/local/slurm/etc/slurm.conf"
echo ""
echo "3️⃣  Munge 재시작:"
echo "   sudo systemctl restart munge"
echo "   sudo systemctl status munge"
echo ""
echo "4️⃣  slurmctld 수동 시작 (디버그 모드):"
echo "   sudo -u slurm slurmctld -D -vvv"
echo ""
echo "5️⃣  systemd 타임아웃 늘리기:"
echo "   sudo systemctl edit slurmctld"
echo "   # 다음 추가:"
echo "   [Service]"
echo "   TimeoutStartSec=300"
echo ""
