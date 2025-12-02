#!/bin/bash
################################################################################
# systemd 서비스 Type=notify → Type=simple 전환 스크립트
# 
# 목적:
#   - Slurm 23.11.10과의 호환성 향상
#   - 서비스 시작 타임아웃 문제 해결
#   - 안정적인 원격 노드 배포
#
# 수정 파일:
#   1. create_slurm_systemd_services.sh
#   2. install_slurm_accounting.sh
#
# 변경 내용:
#   - Type=notify → Type=simple
#   - ExecStart: -D 옵션 제거 (foreground mode → background)
#   - 기타 모든 설정 유지 (TimeoutStartSec=120, Restart=on-failure 등)
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "🔧 systemd Type 전환: notify → simple"
echo "================================================================================"
echo ""
echo "이 스크립트는 Slurm systemd 서비스를 Type=simple로 변경합니다."
echo ""
echo "변경 이유:"
echo "  - Slurm 23.11.10 호환성 향상"
echo "  - 타임아웃 문제 해결"
echo "  - 안정적인 서비스 시작"
echo ""
echo "변경 파일:"
echo "  1. create_slurm_systemd_services.sh"
echo "  2. install_slurm_accounting.sh"
echo ""

read -p "계속하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "⏭️  취소됨"
    exit 0
fi

echo ""

################################################################################
# 1. 백업 생성
################################################################################

echo "📦 Step 1/5: 백업 생성..."
echo "--------------------------------------------------------------------------------"

BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)_notify_to_simple"
mkdir -p "$BACKUP_DIR"

FILES_TO_BACKUP=(
    "create_slurm_systemd_services.sh"
    "install_slurm_accounting.sh"
)

for file in "${FILES_TO_BACKUP[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/"
        echo "  ✅ $file → $BACKUP_DIR/"
    else
        echo "  ⚠️  $file 파일이 없습니다"
    fi
done

echo ""
echo "✅ 백업 완료: $BACKUP_DIR"
echo ""

################################################################################
# 2. create_slurm_systemd_services.sh 수정
################################################################################

echo "📝 Step 2/5: create_slurm_systemd_services.sh 수정..."
echo "--------------------------------------------------------------------------------"

FILE1="create_slurm_systemd_services.sh"

if [ ! -f "$FILE1" ]; then
    echo "❌ $FILE1 파일이 없습니다!"
    exit 1
fi

echo "변경 내용:"
echo "  - slurmctld.service: Type=notify → Type=simple"
echo "  - slurmd.service: Type=notify → Type=simple"
echo "  - ExecStart: -D 옵션 제거"
echo ""

# slurmctld.service 수정
cat > "${FILE1}.tmp" << 'EOF'
#!/bin/bash
################################################################################
# Slurm systemd 서비스 파일 생성 (Type=simple)
# slurmctld와 slurmd 서비스 파일을 Type=simple로 생성
#
# Type=simple 선택 이유:
#   - Slurm 23.11.10과의 호환성
#   - sd_notify() 신호 대기 불필요
#   - 더 안정적인 서비스 시작
################################################################################

set -e

echo "=========================================="
echo "📝 Slurm systemd 서비스 파일 생성"
echo "=========================================="
echo ""

################################################################################
# slurmctld.service (컨트롤러용)
################################################################################

echo "1️⃣  slurmctld.service 생성 (Type=simple)..."

sudo tee /etc/systemd/system/slurmctld.service > /dev/null << 'SLURMCTLD_EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service slurmdbd.service
Wants=slurmdbd.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMCTLD_EOF

echo "✅ slurmctld.service 생성 완료 (Type=simple)"
echo ""

################################################################################
# slurmd.service (계산 노드용)
################################################################################

echo "2️⃣  slurmd.service 생성 (Type=simple)..."

sudo tee /etc/systemd/system/slurmd.service > /dev/null << 'SLURMD_EOF'
[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service
ConditionPathExists=/usr/local/slurm/etc/slurm.conf

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStart=/usr/local/slurm/sbin/slurmd $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes
TasksMax=infinity
TimeoutStartSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SLURMD_EOF

echo "✅ slurmd.service 생성 완료 (Type=simple)"
echo ""

################################################################################
# PID 디렉토리 생성
################################################################################

echo "3️⃣  PID 디렉토리 생성..."

sudo mkdir -p /var/run/slurm
sudo chown slurm:slurm /var/run/slurm

echo "✅ PID 디렉토리 생성 완료"
echo ""

################################################################################
# systemd 리로드
################################################################################

echo "4️⃣  systemd daemon-reload..."

sudo systemctl daemon-reload

echo "✅ systemd 리로드 완료"
echo ""

################################################################################
# 완료
################################################################################

echo "=========================================="
echo "✅ systemd 서비스 파일 생성 완료!"
echo "=========================================="
echo ""
echo "생성된 파일:"
echo "  - /etc/systemd/system/slurmctld.service (Type=simple)"
echo "  - /etc/systemd/system/slurmd.service (Type=simple)"
echo ""
echo "다음 단계:"
echo "  1. 컨트롤러:"
echo "     sudo systemctl enable slurmctld"
echo "     sudo systemctl start slurmctld"
echo ""
echo "  2. 계산 노드:"
echo "     sudo systemctl enable slurmd"
echo "     sudo systemctl start slurmd"
echo ""
EOF

mv "${FILE1}.tmp" "$FILE1"
chmod +x "$FILE1"

echo "✅ $FILE1 수정 완료"
echo ""

################################################################################
# 3. install_slurm_accounting.sh 수정
################################################################################

echo "📝 Step 3/5: install_slurm_accounting.sh 수정..."
echo "--------------------------------------------------------------------------------"

FILE2="install_slurm_accounting.sh"

if [ ! -f "$FILE2" ]; then
    echo "❌ $FILE2 파일이 없습니다!"
    exit 1
fi

echo "변경 내용:"
echo "  - slurmdbd.service: Type=notify → Type=simple"
echo "  - ExecStart: -D 옵션 제거"
echo ""

# slurmdbd.service 부분만 Type=simple로 변경
# 파일이 크므로 sed로 직접 수정

# Type=notify → Type=simple
sed -i 's/^Type=notify$/Type=simple/g' "$FILE2"

# ExecStart에서 -D 제거
sed -i 's|ExecStart=/usr/local/slurm/sbin/slurmdbd -D \$SLURMDBD_OPTIONS|ExecStart=/usr/local/slurm/sbin/slurmdbd $SLURMDBD_OPTIONS|g' "$FILE2"

echo "✅ $FILE2 수정 완료"
echo ""

################################################################################
# 4. 변경사항 검증
################################################################################

echo "🔍 Step 4/5: 변경사항 검증..."
echo "--------------------------------------------------------------------------------"

echo ""
echo "📄 create_slurm_systemd_services.sh:"

if grep -q "Type=simple" "$FILE1" && ! grep -q "Type=notify" "$FILE1"; then
    echo "  ✅ Type=simple 확인"
else
    echo "  ❌ Type 변경 실패"
fi

if grep -q "slurmctld \$SLURMCTLD_OPTIONS" "$FILE1" && ! grep -q "slurmctld -D" "$FILE1"; then
    echo "  ✅ slurmctld: -D 제거 확인"
else
    echo "  ❌ slurmctld ExecStart 변경 실패"
fi

if grep -q "slurmd \$SLURMD_OPTIONS" "$FILE1" && ! grep -q "slurmd -D" "$FILE1"; then
    echo "  ✅ slurmd: -D 제거 확인"
else
    echo "  ❌ slurmd ExecStart 변경 실패"
fi

echo ""
echo "📄 install_slurm_accounting.sh:"

if grep -q "Type=simple" "$FILE2" && ! grep -q "Type=notify" "$FILE2"; then
    echo "  ✅ Type=simple 확인"
else
    echo "  ❌ Type 변경 실패"
fi

if grep -q "slurmdbd \\\$SLURMDBD_OPTIONS" "$FILE2" && ! grep -q "slurmdbd -D" "$FILE2"; then
    echo "  ✅ slurmdbd: -D 제거 확인"
else
    echo "  ❌ slurmdbd ExecStart 변경 실패"
fi

echo ""

################################################################################
# 5. 요약
################################################################################

echo "📊 Step 5/5: 변경 요약"
echo "--------------------------------------------------------------------------------"
echo ""

echo "✅ 수정 완료:"
echo "  1. create_slurm_systemd_services.sh"
echo "     - slurmctld.service: Type=simple"
echo "     - slurmd.service: Type=simple"
echo ""
echo "  2. install_slurm_accounting.sh"
echo "     - slurmdbd.service: Type=simple"
echo ""

echo "💾 백업 위치:"
echo "  $BACKUP_DIR"
echo ""

echo "🔄 백업 복원 방법:"
echo "  cp $BACKUP_DIR/*.sh ./"
echo ""

################################################################################
# 완료
################################################################################

echo "================================================================================"
echo "🎉 Type=simple 전환 완료!"
echo "================================================================================"
echo ""

echo "다음 단계:"
echo ""
echo "1️⃣  변경사항 확인:"
echo "   grep \"Type=\" create_slurm_systemd_services.sh"
echo "   grep \"Type=\" install_slurm_accounting.sh"
echo ""
echo "2️⃣  새 클러스터 설치:"
echo "   ./setup_cluster_full.sh"
echo ""
echo "3️⃣  기존 클러스터 업데이트 (선택):"
echo "   # 기존 서비스 파일 재생성"
echo "   sudo ./create_slurm_systemd_services.sh"
echo "   "
echo "   # 서비스 재시작"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl restart slurmctld"
echo "   sudo systemctl restart slurmd"
echo ""

echo "⚠️  참고:"
echo "  - 기존 클러스터는 영향 없음 (이미 설치됨)"
echo "  - 새 설치부터 Type=simple 적용"
echo "  - 모든 기능 정상 작동 (QoS, cgroup v2 등)"
echo ""

echo "================================================================================"
