#!/bin/bash
################################################################################
# Slurm PATH 빠른 수정 스크립트
# sinfo, sbatch 등 명령어를 즉시 사용 가능하게 만듭니다
################################################################################

echo "================================================================================"
echo "⚡ Slurm PATH 빠른 수정"
echo "================================================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# 1. Slurm 설치 확인
################################################################################

if [ ! -d "/usr/local/slurm/bin" ]; then
    echo -e "${RED}❌ /usr/local/slurm/bin 디렉토리가 없습니다!${NC}"
    echo ""
    echo "Slurm이 설치되어 있지 않거나 다른 위치에 설치되었을 수 있습니다."
    echo ""
    echo "다른 위치 확인:"
    echo "  find /usr -name sinfo 2>/dev/null"
    echo "  find /opt -name sinfo 2>/dev/null"
    exit 1
fi

echo "✅ Slurm 바이너리 확인됨: /usr/local/slurm/bin"
echo ""

################################################################################
# 2. /etc/profile.d/slurm.sh 생성/확인
################################################################################

echo "📝 /etc/profile.d/slurm.sh 파일 확인 중..."

PROFILE_FILE="/etc/profile.d/slurm.sh"

if [ -f "$PROFILE_FILE" ]; then
    echo "✅ 파일이 이미 존재합니다"
else
    echo "⚠️  파일이 없습니다. 생성합니다..."
    
    sudo tee "$PROFILE_FILE" > /dev/null << 'EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
EOF
    
    sudo chmod 644 "$PROFILE_FILE"
    echo "✅ 파일 생성 완료"
fi

echo ""

################################################################################
# 3. 현재 터미널에 PATH 적용
################################################################################

echo "⚡ 현재 터미널에 PATH 적용 중..."

# profile.d 파일 로드
source "$PROFILE_FILE"

# 추가 PATH 설정 (중복 방지)
if ! echo "$PATH" | grep -q "/usr/local/slurm/bin"; then
    export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
fi

echo "✅ PATH 적용 완료"
echo ""

################################################################################
# 4. 명령어 확인
################################################################################

echo "🧪 명령어 확인..."
echo ""

ALL_OK=true

for cmd in sinfo squeue sbatch srun scancel; do
    if command -v "$cmd" &> /dev/null; then
        LOCATION=$(which "$cmd")
        echo -e "  ${GREEN}✅${NC} $cmd → $LOCATION"
    else
        echo -e "  ${RED}❌${NC} $cmd (not found)"
        ALL_OK=false
    fi
done

echo ""

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✅ 모든 명령어가 정상적으로 설정되었습니다!${NC}"
    echo ""
    
    # 버전 확인
    VERSION=$(sinfo --version 2>/dev/null | head -1)
    if [ -n "$VERSION" ]; then
        echo "📊 $VERSION"
    fi
else
    echo -e "${RED}❌ 일부 명령어를 찾을 수 없습니다.${NC}"
    echo ""
    echo "문제 해결:"
    echo "  1. Slurm이 올바르게 설치되었는지 확인"
    echo "  2. /usr/local/slurm/bin 디렉토리 확인"
    echo "  3. 설치 스크립트 재실행"
fi

echo ""
echo "================================================================================"
echo "📋 다음 단계"
echo "================================================================================"
echo ""

if [ "$ALL_OK" = true ]; then
    echo "1️⃣  현재 터미널에서 바로 사용 가능:"
    echo "   sinfo"
    echo "   squeue"
    echo "   sbatch test.sh"
    echo ""
    echo "2️⃣  새 터미널에서도 자동으로 사용 가능 (이미 설정됨)"
    echo "   /etc/profile.d/slurm.sh가 자동으로 로드됩니다"
    echo ""
    echo "3️⃣  만약 새 터미널에서도 안 된다면:"
    echo "   ~/.bashrc에 추가:"
    echo "   echo 'source /etc/profile.d/slurm.sh' >> ~/.bashrc"
    echo ""
    echo "4️⃣  클러스터 상태 확인:"
    echo "   sinfo"
    echo "   sinfo -N"
    echo "   scontrol show node"
else
    echo "⚠️  명령어 설정에 실패했습니다."
    echo ""
    echo "수동 확인:"
    echo "  ls -la /usr/local/slurm/bin/"
    echo "  /usr/local/slurm/bin/sinfo --version"
    echo ""
    echo "상세 진단:"
    echo "  ./diagnose_slurm_path.sh"
fi

echo ""
echo "================================================================================"
echo ""

# 사용자 셸 설정 파일 업데이트 제안
if [ "$ALL_OK" = true ]; then
    if ! grep -q "slurm.sh" ~/.bashrc 2>/dev/null && ! grep -q "/usr/local/slurm/bin" ~/.bashrc 2>/dev/null; then
        echo ""
        read -p "~/.bashrc에도 PATH를 추가하시겠습니까? (권장) (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "" >> ~/.bashrc
            echo "# Slurm PATH" >> ~/.bashrc
            echo "source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:\$PATH" >> ~/.bashrc
            echo ""
            echo -e "${GREEN}✅ ~/.bashrc에 추가되었습니다!${NC}"
            echo ""
            echo "이제 모든 새 터미널에서 자동으로 Slurm 명령어를 사용할 수 있습니다."
        fi
    fi
fi

echo ""
