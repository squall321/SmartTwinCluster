#!/bin/bash
# ========================================================================
# Moonlight/Sunshine Slurm QoS 생성 스크립트 (Step 2)
# ========================================================================
# 목적: Moonlight 전용 Slurm QoS 생성
# 위치: Controller에서 실행
# 권한: sudo 필요
# 소요시간: 5분
# ========================================================================

set -e  # 에러 발생 시 즉시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# ========================================================================
# 1. 환경 확인
# ========================================================================

log_info "Step 2: Slurm QoS 생성 시작"
log_info ""

# sacctmgr 설치 확인
log_info "Slurm 설치 확인 중..."
if ! command -v sacctmgr &> /dev/null; then
    log_error "sacctmgr를 찾을 수 없습니다"
    log_error "Slurm이 설치되어 있지 않습니다"
    exit 1
fi

SLURM_VERSION=$(scontrol --version | head -1)
log_info "✅ Slurm 버전: $SLURM_VERSION"

# sudo 권한 확인
log_info "sudo 권한 확인 중..."
if ! sudo -n sacctmgr show qos &>/dev/null; then
    log_warn "sudo 권한이 필요합니다"
    sudo -v
fi
log_info "✅ sudo 권한 확인 완료"

# ========================================================================
# 2. 기존 QoS 확인
# ========================================================================

log_info ""
log_info "기존 QoS 목록 확인 중..."
log_info "=========================================="
sudo sacctmgr show qos format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p
log_info "=========================================="

# moonlight QoS 존재 여부 확인
if sudo sacctmgr show qos moonlight -p 2>/dev/null | grep -q "^moonlight|"; then
    log_warn ""
    log_warn "⚠️  'moonlight' QoS가 이미 존재합니다"
    log_warn ""
    read -p "기존 QoS를 삭제하고 다시 생성하시겠습니까? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "기존 'moonlight' QoS 삭제 중..."
        sudo sacctmgr -i delete qos moonlight
        log_info "✅ 기존 QoS 삭제 완료"
    else
        log_info "기존 QoS 유지, 설정만 업데이트합니다"
    fi
fi

# ========================================================================
# 3. Moonlight QoS 생성
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Moonlight QoS 생성 중..."
log_info "=========================================="

# QoS 파라미터 정의
QOS_NAME="moonlight"
QOS_PRIORITY="100"
QOS_GRACE_TIME="60"
QOS_MAX_WALL="8:00:00"
QOS_MAX_TRES_PER_USER="gpu=2"
QOS_DESCRIPTION="Moonlight/Sunshine ultra-low latency streaming"

log_info "QoS 설정:"
log_info "  Name: $QOS_NAME"
log_info "  Priority: $QOS_PRIORITY"
log_info "  GraceTime: $QOS_GRACE_TIME seconds"
log_info "  MaxWall: $QOS_MAX_WALL"
log_info "  MaxTRESPerUser: $QOS_MAX_TRES_PER_USER"
log_info ""

# QoS 생성 또는 업데이트
if sudo sacctmgr show qos moonlight -p 2>/dev/null | grep -q "^moonlight|"; then
    # 기존 QoS 업데이트
    log_info "기존 QoS 설정 업데이트 중..."

    sudo sacctmgr -i modify qos "$QOS_NAME" set \
        Priority="$QOS_PRIORITY" \
        GraceTime="$QOS_GRACE_TIME" \
        MaxWall="$QOS_MAX_WALL" \
        MaxTRESPerUser="$QOS_MAX_TRES_PER_USER"

    log_info "✅ QoS 업데이트 완료"
else
    # 새 QoS 생성
    log_info "새 QoS 생성 중..."

    sudo sacctmgr -i add qos "$QOS_NAME"

    sudo sacctmgr -i modify qos "$QOS_NAME" set \
        Priority="$QOS_PRIORITY" \
        GraceTime="$QOS_GRACE_TIME" \
        MaxWall="$QOS_MAX_WALL" \
        MaxTRESPerUser="$QOS_MAX_TRES_PER_USER"

    log_info "✅ QoS 생성 완료"
fi

# ========================================================================
# 4. QoS 확인
# ========================================================================

log_info ""
log_info "=========================================="
log_info "생성된 QoS 확인"
log_info "=========================================="

QOS_INFO=$(sudo sacctmgr show qos "$QOS_NAME" format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p)

if [ -z "$QOS_INFO" ] || ! echo "$QOS_INFO" | grep -q "^moonlight|"; then
    log_error "QoS 생성 실패"
    log_error "다시 시도해주세요"
    exit 1
fi

echo "$QOS_INFO"

# 파싱하여 검증
QOS_ACTUAL_PRIORITY=$(echo "$QOS_INFO" | grep "^moonlight|" | cut -d'|' -f2)
QOS_ACTUAL_MAXWALL=$(echo "$QOS_INFO" | grep "^moonlight|" | cut -d'|' -f3)
QOS_ACTUAL_MAXTRES=$(echo "$QOS_INFO" | grep "^moonlight|" | cut -d'|' -f4)
QOS_ACTUAL_GRACE=$(echo "$QOS_INFO" | grep "^moonlight|" | cut -d'|' -f5)

log_info ""
log_info "설정 확인:"
log_info "  Priority: $QOS_ACTUAL_PRIORITY (expected: $QOS_PRIORITY)"
log_info "  MaxWall: $QOS_ACTUAL_MAXWALL (expected: $QOS_MAX_WALL)"
log_info "  MaxTRESPerUser: $QOS_ACTUAL_MAXTRES (expected: $QOS_MAX_TRES_PER_USER)"
log_info "  GraceTime: $QOS_ACTUAL_GRACE (expected: $QOS_GRACE_TIME)"

# ========================================================================
# 5. 사용자 QoS 권한 확인 (선택사항)
# ========================================================================

log_info ""
log_info "=========================================="
log_info "사용자 QoS 권한 확인"
log_info "=========================================="

CURRENT_USER=$(whoami)

log_info "현재 사용자: $CURRENT_USER"
log_info ""

USER_QOS=$(sudo sacctmgr show user "$CURRENT_USER" format=User,QOS -p 2>/dev/null)

if [ -n "$USER_QOS" ]; then
    echo "$USER_QOS"

    if echo "$USER_QOS" | grep -q "moonlight"; then
        log_info "✅ 사용자 $CURRENT_USER는 moonlight QoS 사용 가능"
    else
        log_warn "⚠️  사용자 $CURRENT_USER는 moonlight QoS를 사용할 수 없습니다"
        log_warn ""
        read -p "사용자에게 moonlight QoS를 추가하시겠습니까? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "사용자 QoS 추가 중..."
            sudo sacctmgr -i modify user "$CURRENT_USER" set qos+=moonlight
            log_info "✅ QoS 추가 완료"
        fi
    fi
else
    log_warn "사용자 정보를 가져올 수 없습니다"
fi

# ========================================================================
# 6. 테스트 Job 제출 (선택사항)
# ========================================================================

log_info ""
log_info "=========================================="
log_info "테스트 Job 제출 (선택사항)"
log_info "=========================================="

read -p "Moonlight QoS로 테스트 Job을 제출하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "테스트 Job 생성 중..."

    TEST_SCRIPT="/tmp/test_moonlight_qos_$$.sh"

    cat > "$TEST_SCRIPT" <<'EOF'
#!/bin/bash
#SBATCH --job-name=test-moonlight-qos
#SBATCH --partition=viz
#SBATCH --qos=moonlight
#SBATCH --gres=gpu:1
#SBATCH --time=00:05:00
#SBATCH --output=/tmp/test_moonlight_qos_%j.log

echo "=========================================="
echo "Moonlight QoS 테스트 Job"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURMD_NODENAME"
echo "QoS: $SLURM_JOB_QOS"
echo "GPUs: $CUDA_VISIBLE_DEVICES"
echo "=========================================="

if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
else
    echo "nvidia-smi not found"
fi

sleep 10

echo "테스트 완료"
EOF

    log_info "테스트 Job 제출 중..."
    JOB_ID=$(sbatch "$TEST_SCRIPT" | awk '{print $NF}')

    if [ -n "$JOB_ID" ]; then
        log_info "✅ Job 제출 완료: Job ID = $JOB_ID"
        log_info ""
        log_info "Job 상태 확인:"
        squeue -j "$JOB_ID" -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %.6C %R %q"
        log_info ""
        log_info "로그 파일: /tmp/test_moonlight_qos_${JOB_ID}.log"
        log_info ""
        log_info "Job 취소: scancel $JOB_ID"
    else
        log_error "Job 제출 실패"
    fi

    rm -f "$TEST_SCRIPT"
else
    log_info "테스트 Job 제출을 건너뜁니다"
fi

# ========================================================================
# 7. 완료
# ========================================================================

log_info ""
log_info "=========================================="
log_info "🎉 Step 2: Slurm QoS 생성 완료!"
log_info "=========================================="
log_info ""
log_info "생성된 QoS: moonlight"
log_info ""
log_info "QoS 사용 예시:"
log_info "  #SBATCH --qos=moonlight"
log_info ""
log_info "다음 단계:"
log_info "  Step 3 실행: deploy_step3_nginx.sh"
log_info ""

# ========================================================================
# 참고 명령어
# ========================================================================

log_info "=========================================="
log_info "참고 명령어"
log_info "=========================================="
echo ""
echo "# QoS 목록 보기"
echo "sacctmgr show qos"
echo ""
echo "# Moonlight QoS 상세 정보"
echo "sacctmgr show qos moonlight format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p"
echo ""
echo "# 사용자 QoS 권한 확인"
echo "sacctmgr show user \$USER format=User,QOS -p"
echo ""
echo "# QoS 수정"
echo "sudo sacctmgr modify qos moonlight set Priority=150"
echo ""
echo "# QoS 삭제 (주의!)"
echo "sudo sacctmgr delete qos moonlight"
echo ""
