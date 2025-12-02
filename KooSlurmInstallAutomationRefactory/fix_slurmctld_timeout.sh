#!/bin/bash
################################################################################
# slurmctld 타임아웃 자동 수정 스크립트
################################################################################

set -e

echo "========================================"
echo "🔧 slurmctld 타임아웃 자동 수정"
echo "========================================"
echo ""

# Slurm 사용자 확인
SLURM_USER="slurm"
if ! id "$SLURM_USER" &>/dev/null; then
    echo "❌ slurm 사용자가 없습니다. 생성합니다..."
    sudo useradd -r -M -d /nonexistent -s /bin/false slurm
    echo "✅ slurm 사용자 생성 완료"
fi

echo "📁 Step 1: 필수 디렉토리 생성 및 권한 설정"
echo "----------------------------------------"

# 필수 디렉토리 생성
sudo mkdir -p /var/spool/slurm/state
sudo mkdir -p /var/spool/slurm/ctld
sudo mkdir -p /var/log/slurm
sudo mkdir -p /var/run/slurm

# 권한 설정
sudo chown -R slurm:slurm /var/spool/slurm
sudo chown -R slurm:slurm /var/log/slurm
sudo chown -R slurm:slurm /var/run/slurm

sudo chmod 755 /var/spool/slurm
sudo chmod 755 /var/spool/slurm/state
sudo chmod 755 /var/spool/slurm/ctld
sudo chmod 755 /var/log/slurm
sudo chmod 755 /var/run/slurm

echo "✅ 디렉토리 권한 설정 완료"
echo ""

echo "🔧 Step 2: Slurm 설정 파일 권한 수정"
echo "----------------------------------------"

# 설정 파일 위치 찾기
SLURM_CONF=""
for path in /usr/local/slurm/etc/slurm.conf /etc/slurm/slurm.conf; do
    if [ -f "$path" ]; then
        SLURM_CONF="$path"
        break
    fi
done

if [ -z "$SLURM_CONF" ]; then
    echo "❌ slurm.conf 파일을 찾을 수 없습니다"
    exit 1
fi

echo "설정 파일: $SLURM_CONF"
sudo chown slurm:slurm "$SLURM_CONF"
sudo chmod 644 "$SLURM_CONF"
echo "✅ 설정 파일 권한 수정 완료"
echo ""

echo "🔄 Step 3: Munge 서비스 재시작"
echo "----------------------------------------"
if systemctl is-active --quiet munge; then
    sudo systemctl restart munge
    echo "✅ Munge 재시작 완료"
else
    sudo systemctl start munge
    echo "✅ Munge 시작 완료"
fi

# Munge 상태 확인
if systemctl is-active --quiet munge; then
    echo "✅ Munge 정상 작동 중"
else
    echo "❌ Munge 시작 실패"
    systemctl status munge --no-pager
    exit 1
fi
echo ""

echo "⏱️  Step 4: systemd 타임아웃 설정 확대"
echo "----------------------------------------"

# systemd override 디렉토리 생성
sudo mkdir -p /etc/systemd/system/slurmctld.service.d

# override 파일 생성
sudo tee /etc/systemd/system/slurmctld.service.d/timeout.conf > /dev/null <<EOF
[Service]
TimeoutStartSec=300
TimeoutStopSec=300
EOF

echo "✅ systemd 타임아웃 300초로 설정"

# systemd 리로드
sudo systemctl daemon-reload
echo "✅ systemd 설정 리로드 완료"
echo ""

echo "🧹 Step 5: 기존 PID 파일 정리"
echo "----------------------------------------"
sudo rm -f /var/run/slurm/slurmctld.pid
sudo rm -f /var/run/slurmctld.pid
echo "✅ PID 파일 정리 완료"
echo ""

echo "🔍 Step 6: 설정 파일 구문 검증"
echo "----------------------------------------"
if command -v slurm &> /dev/null; then
    if slurm -f "$SLURM_CONF" -C 2>&1 | grep -q "error"; then
        echo "❌ slurm.conf에 오류가 있습니다:"
        slurm -f "$SLURM_CONF" -C
        exit 1
    else
        echo "✅ slurm.conf 구문 검증 통과"
    fi
else
    echo "⚠️  slurm 명령어를 찾을 수 없어 검증 생략"
fi
echo ""

echo "🚀 Step 7: slurmctld 서비스 시작"
echo "----------------------------------------"

# 기존 서비스 중지
sudo systemctl stop slurmctld 2>/dev/null || true
sleep 2

# 서비스 시작
echo "slurmctld 시작 중... (최대 300초 대기)"
if sudo systemctl start slurmctld; then
    echo "✅ slurmctld 시작 성공"
    
    # 상태 확인
    sleep 3
    systemctl status slurmctld --no-pager -l
    
    echo ""
    echo "✅ slurmctld 서비스 활성화 중..."
    sudo systemctl enable slurmctld
    
else
    echo "❌ slurmctld 시작 실패"
    echo ""
    echo "📋 상세 로그:"
    journalctl -u slurmctld.service -n 50 --no-pager
    echo ""
    echo "💡 수동 디버깅:"
    echo "   sudo -u slurm slurmctld -D -vvv"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ 수정 완료!"
echo "========================================"
echo ""
echo "📊 서비스 상태 확인:"
echo "   systemctl status slurmctld"
echo ""
echo "📋 실시간 로그 확인:"
echo "   journalctl -u slurmctld -f"
echo ""
echo "🧪 Slurm 테스트:"
echo "   sinfo"
echo "   scontrol show node"
echo ""
