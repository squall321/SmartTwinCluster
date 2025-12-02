#!/bin/bash
################################################################################
# Slurm PATH 문제 진단 및 해결 스크립트
################################################################################

echo "================================================================================"
echo "🔍 Slurm 명령어 PATH 문제 진단"
echo "================================================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# 1. Slurm 바이너리 파일 존재 확인
################################################################################

echo "📁 Step 1: Slurm 바이너리 파일 확인..."
echo "--------------------------------------------------------------------------------"

SLURM_BIN="/usr/local/slurm/bin"
SLURM_SBIN="/usr/local/slurm/sbin"

if [ -d "$SLURM_BIN" ]; then
    echo -e "${GREEN}✅ $SLURM_BIN 디렉토리 존재${NC}"
    echo ""
    echo "   주요 명령어 확인:"
    for cmd in sinfo squeue sbatch srun scancel sacct; do
        if [ -f "$SLURM_BIN/$cmd" ]; then
            echo -e "   ${GREEN}✅${NC} $cmd"
        else
            echo -e "   ${RED}❌${NC} $cmd (없음)"
        fi
    done
else
    echo -e "${RED}❌ $SLURM_BIN 디렉토리가 없습니다!${NC}"
    echo ""
    echo "Slurm이 설치되지 않았거나 다른 위치에 설치되었을 수 있습니다."
    echo ""
    echo "설치 확인:"
    echo "  find /usr -name sinfo 2>/dev/null"
    echo "  find /opt -name sinfo 2>/dev/null"
    echo "  find /local -name sinfo 2>/dev/null"
    exit 1
fi

echo ""

################################################################################
# 2. /etc/profile.d/slurm.sh 파일 확인
################################################################################

echo "📄 Step 2: /etc/profile.d/slurm.sh 파일 확인..."
echo "--------------------------------------------------------------------------------"

PROFILE_FILE="/etc/profile.d/slurm.sh"

if [ -f "$PROFILE_FILE" ]; then
    echo -e "${GREEN}✅ $PROFILE_FILE 파일 존재${NC}"
    echo ""
    echo "   내용:"
    cat "$PROFILE_FILE" | sed 's/^/   /'
    echo ""
    
    # 권한 확인
    PERMS=$(stat -c "%a" "$PROFILE_FILE" 2>/dev/null || stat -f "%OLp" "$PROFILE_FILE" 2>/dev/null)
    echo "   권한: $PERMS"
    
    if [ "$PERMS" = "644" ] || [ "$PERMS" = "755" ]; then
        echo -e "   ${GREEN}✅ 권한 정상${NC}"
    else
        echo -e "   ${YELLOW}⚠️  권한이 이상합니다. 644 또는 755여야 합니다.${NC}"
        echo "   수정: sudo chmod 644 $PROFILE_FILE"
    fi
else
    echo -e "${RED}❌ $PROFILE_FILE 파일이 없습니다!${NC}"
    echo ""
    echo "파일을 생성하겠습니까?"
    read -p "생성하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo "파일 생성 중..."
        sudo tee "$PROFILE_FILE" > /dev/null << 'EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
EOF
        sudo chmod 644 "$PROFILE_FILE"
        echo -e "${GREEN}✅ 파일 생성 완료${NC}"
    fi
fi

echo ""

################################################################################
# 3. 현재 PATH 확인
################################################################################

echo "🛤️  Step 3: 현재 PATH 확인..."
echo "--------------------------------------------------------------------------------"

if echo "$PATH" | grep -q "/usr/local/slurm/bin"; then
    echo -e "${GREEN}✅ 현재 PATH에 Slurm 경로 포함됨${NC}"
    echo ""
    echo "   PATH에서 Slurm 관련 경로:"
    echo "$PATH" | tr ':' '\n' | grep slurm | sed 's/^/   /'
else
    echo -e "${YELLOW}⚠️  현재 PATH에 Slurm 경로 없음${NC}"
    echo ""
    echo "   현재 PATH:"
    echo "$PATH" | tr ':' '\n' | head -5 | sed 's/^/   /'
    echo "   ..."
fi

echo ""

################################################################################
# 4. 명령어 실행 테스트
################################################################################

echo "🧪 Step 4: 명령어 실행 테스트..."
echo "--------------------------------------------------------------------------------"

# which로 확인
echo "which 명령어로 확인:"
for cmd in sinfo squeue sbatch; do
    LOCATION=$(which $cmd 2>/dev/null)
    if [ -n "$LOCATION" ]; then
        echo -e "  ${GREEN}✅${NC} $cmd → $LOCATION"
    else
        echo -e "  ${RED}❌${NC} $cmd (not found)"
    fi
done

echo ""

# 직접 경로로 실행
echo "직접 경로로 실행:"
if [ -f "$SLURM_BIN/sinfo" ]; then
    VERSION=$($SLURM_BIN/sinfo --version 2>/dev/null | head -1)
    if [ -n "$VERSION" ]; then
        echo -e "  ${GREEN}✅${NC} $SLURM_BIN/sinfo 실행 가능"
        echo "     $VERSION"
    else
        echo -e "  ${RED}❌${NC} $SLURM_BIN/sinfo 실행 실패"
    fi
else
    echo -e "  ${RED}❌${NC} $SLURM_BIN/sinfo 파일 없음"
fi

echo ""

################################################################################
# 5. 해결 방법 제시
################################################################################

echo "================================================================================"
echo "🔧 해결 방법"
echo "================================================================================"
echo ""

if echo "$PATH" | grep -q "/usr/local/slurm/bin"; then
    echo -e "${GREEN}✅ PATH가 올바르게 설정되어 있습니다!${NC}"
    echo ""
    echo "명령어를 사용할 수 있습니다:"
    echo "  sinfo"
    echo "  squeue"
    echo "  sbatch test.sh"
else
    echo -e "${YELLOW}⚠️  PATH 설정이 필요합니다!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "${BLUE}방법 1: 현재 터미널에서만 적용 (임시)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "다음 명령어를 실행하세요:"
    echo ""
    echo -e "${GREEN}source /etc/profile.d/slurm.sh${NC}"
    echo ""
    echo "또는:"
    echo ""
    echo -e "${GREEN}export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:\$PATH${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "${BLUE}방법 2: 영구 적용 (새 터미널에서도 자동)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "~/.bashrc에 추가:"
    echo ""
    echo -e "${GREEN}echo 'export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:\$PATH' >> ~/.bashrc${NC}"
    echo -e "${GREEN}source ~/.bashrc${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "${BLUE}방법 3: 새 터미널 열기 (가장 간단)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "/etc/profile.d/slurm.sh가 있으면 새 터미널에서 자동으로 로드됩니다."
    echo ""
    echo "1. 현재 터미널을 닫고"
    echo "2. 새 터미널을 열고"
    echo "3. sinfo 명령어를 입력해보세요"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "${BLUE}방법 4: 절대 경로로 실행 (임시 해결)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "PATH 설정 없이 바로 사용:"
    echo ""
    echo -e "${GREEN}/usr/local/slurm/bin/sinfo${NC}"
    echo -e "${GREEN}/usr/local/slurm/bin/squeue${NC}"
    echo -e "${GREEN}/usr/local/slurm/bin/sbatch test.sh${NC}"
    echo ""
fi

echo "================================================================================"
echo ""

# 자동 수정 제안
if ! echo "$PATH" | grep -q "/usr/local/slurm/bin"; then
    echo ""
    read -p "지금 바로 현재 터미널에 PATH를 적용하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo "PATH 적용 중..."
        export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
        echo -e "${GREEN}✅ PATH 적용 완료!${NC}"
        echo ""
        echo "이제 명령어를 사용할 수 있습니다:"
        echo ""
        which sinfo 2>/dev/null && echo "  ✅ sinfo: $(which sinfo)"
        which squeue 2>/dev/null && echo "  ✅ squeue: $(which squeue)"
        which sbatch 2>/dev/null && echo "  ✅ sbatch: $(which sbatch)"
        echo ""
        echo "테스트:"
        echo "  sinfo --version"
        echo ""
    fi
fi
