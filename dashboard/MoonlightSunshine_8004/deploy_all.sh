#!/bin/bash
# ========================================================================
# Moonlight/Sunshine 전체 배포 자동화 스크립트
# ========================================================================
# 목적: Moonlight/Sunshine 시스템 전체 배포 자동화
# 위치: Controller에서 실행 (Step 1은 viz-node로 자동 전환)
# 권한: sudo 필요, viz-node SSH 접근 필요
# 소요시간: 75-105분
# ========================================================================

set -e  # 에러 발생 시 즉시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_success() {
    echo -e "${MAGENTA}[SUCCESS]${NC} $1"
}

# ========================================================================
# 배포 시작
# ========================================================================

clear
cat << 'EOF'
========================================
  Moonlight/Sunshine 전체 배포
========================================
  Ultra-Low Latency Streaming for HPC
========================================

배포 단계:
  Step 1: Apptainer 이미지 빌드 (viz-node)
  Step 2: Slurm QoS 생성 (Controller)
  Step 3: Nginx 설정 적용 (Controller)

예상 소요시간: 75-105분

EOF

read -p "배포를 시작하시겠습니까? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "사용자가 배포를 취소했습니다"
    exit 1
fi

# 배포 시작 시각
DEPLOY_START_TIME=$(date +%s)
log_info "배포 시작: $(date)"
log_info ""

# ========================================================================
# 사전 확인
# ========================================================================

log_step "=========================================="
log_step "사전 확인"
log_step "=========================================="

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_info "스크립트 디렉토리: $SCRIPT_DIR"

cd "$SCRIPT_DIR"

# 필요한 스크립트 파일 확인
REQUIRED_SCRIPTS=(
    "deploy_step1_build_images.sh"
    "deploy_step2_create_qos.sh"
    "deploy_step3_nginx.sh"
)

for SCRIPT in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$SCRIPT" ]; then
        log_error "필요한 스크립트를 찾을 수 없습니다: $SCRIPT"
        exit 1
    fi
    log_info "✅ $SCRIPT"
done

# sudo 권한 확인
log_info ""
log_info "sudo 권한 확인 중..."
if ! sudo -n true 2>/dev/null; then
    log_warn "sudo 권한이 필요합니다"
    sudo -v
fi
log_info "✅ sudo 권한 확인 완료"

# viz-node SSH 접근 확인
log_info ""
log_info "viz-node SSH 접근 확인 중..."
VIZ_NODE="viz-node001"

if ssh -o ConnectTimeout=5 -o BatchMode=yes "$VIZ_NODE" exit &>/dev/null; then
    log_info "✅ viz-node SSH 접근 가능 (패스워드 없음)"
    VIZ_NODE_SSH_OK=true
else
    log_warn "⚠️  viz-node SSH 접근 실패 (패스워드 필요하거나 접근 불가)"
    log_warn "Step 1을 수동으로 실행해야 합니다"
    VIZ_NODE_SSH_OK=false
fi

# Backend 실행 확인
log_info ""
log_info "Moonlight Backend 실행 확인 중..."
if lsof -i :8004 &>/dev/null; then
    log_info "✅ Moonlight Backend 실행 중 (Port 8004)"
else
    log_warn "⚠️  Moonlight Backend가 실행되지 않았습니다"
    log_warn "배포 완료 후 Backend를 시작해주세요"
fi

log_info ""
log_info "=========================================="
log_info "사전 확인 완료"
log_info "=========================================="
log_info ""

sleep 2

# ========================================================================
# Step 1: Apptainer 이미지 빌드
# ========================================================================

log_step ""
log_step "=========================================="
log_step "Step 1/3: Apptainer 이미지 빌드"
log_step "=========================================="
log_step ""

STEP1_START=$(date +%s)

if [ "$VIZ_NODE_SSH_OK" = true ]; then
    log_info "viz-node로 SSH 연결하여 빌드 스크립트 실행 중..."
    log_info "위치: $VIZ_NODE"
    log_info ""

    # viz-node로 스크립트 복사
    log_info "스크립트 파일 복사 중..."
    scp deploy_step1_build_images.sh "$VIZ_NODE:/tmp/" || {
        log_error "스크립트 복사 실패"
        exit 1
    }

    # 필요한 빌드 파일도 복사
    log_info "빌드 파일 복사 중..."
    scp build_sunshine_images.sh build_from_vnc_images.sh "$VIZ_NODE:/tmp/" || {
        log_error "빌드 파일 복사 실패"
        exit 1
    }

    scp sunshine_desktop.def sunshine_gnome.def sunshine_gnome_lsprepost.def "$VIZ_NODE:/tmp/" || {
        log_error "Definition 파일 복사 실패"
        exit 1
    }

    log_info "✅ 파일 복사 완료"
    log_info ""

    # viz-node에서 스크립트 실행
    log_info "viz-node에서 빌드 스크립트 실행 중..."
    log_info "이 작업은 60-90분이 소요됩니다..."
    log_info ""

    ssh -t "$VIZ_NODE" "cd /tmp && chmod +x deploy_step1_build_images.sh && sudo bash deploy_step1_build_images.sh" || {
        log_error "viz-node에서 빌드 실패"
        exit 1
    }

    log_info ""
    log_success "✅ Step 1 완료: Apptainer 이미지 빌드 성공"
else
    log_warn ""
    log_warn "=========================================="
    log_warn "⚠️  Step 1 수동 실행 필요"
    log_warn "=========================================="
    log_warn ""
    log_warn "viz-node에 직접 접속하여 다음 명령어를 실행하세요:"
    log_warn ""
    log_warn "  ssh viz-node001"
    log_warn "  cd /tmp"
    log_warn "  # Controller에서 파일 복사"
    log_warn "  scp controller:/path/to/deploy_step1_build_images.sh ."
    log_warn "  sudo bash deploy_step1_build_images.sh"
    log_warn ""
    read -p "Step 1 완료 후 Enter를 눌러 계속하세요..."
fi

STEP1_END=$(date +%s)
STEP1_ELAPSED=$((STEP1_END - STEP1_START))
STEP1_MIN=$((STEP1_ELAPSED / 60))

log_info ""
log_info "Step 1 소요시간: ${STEP1_MIN}분 (${STEP1_ELAPSED}초)"
log_info ""

sleep 2

# ========================================================================
# Step 2: Slurm QoS 생성
# ========================================================================

log_step ""
log_step "=========================================="
log_step "Step 2/3: Slurm QoS 생성"
log_step "=========================================="
log_step ""

STEP2_START=$(date +%s)

if bash deploy_step2_create_qos.sh; then
    log_success "✅ Step 2 완료: Slurm QoS 생성 성공"
else
    log_error "❌ Step 2 실패: Slurm QoS 생성 실패"
    log_error "수동으로 실행해주세요: bash deploy_step2_create_qos.sh"
    exit 1
fi

STEP2_END=$(date +%s)
STEP2_ELAPSED=$((STEP2_END - STEP2_START))

log_info ""
log_info "Step 2 소요시간: ${STEP2_ELAPSED}초"
log_info ""

sleep 2

# ========================================================================
# Step 3: Nginx 설정 적용
# ========================================================================

log_step ""
log_step "=========================================="
log_step "Step 3/3: Nginx 설정 적용"
log_step "=========================================="
log_step ""

STEP3_START=$(date +%s)

if bash deploy_step3_nginx.sh; then
    log_success "✅ Step 3 완료: Nginx 설정 적용 성공"
else
    log_error "❌ Step 3 실패: Nginx 설정 적용 실패"
    log_error "수동으로 실행해주세요: bash deploy_step3_nginx.sh"
    exit 1
fi

STEP3_END=$(date +%s)
STEP3_ELAPSED=$((STEP3_END - STEP3_START))

log_info ""
log_info "Step 3 소요시간: ${STEP3_ELAPSED}초"
log_info ""

sleep 2

# ========================================================================
# 배포 완료
# ========================================================================

DEPLOY_END_TIME=$(date +%s)
DEPLOY_TOTAL_ELAPSED=$((DEPLOY_END_TIME - DEPLOY_START_TIME))
DEPLOY_TOTAL_MIN=$((DEPLOY_TOTAL_ELAPSED / 60))

clear
cat << EOF
========================================
  🎉 배포 완료!
========================================

총 소요시간: ${DEPLOY_TOTAL_MIN}분 (${DEPLOY_TOTAL_ELAPSED}초)

  ✅ Step 1: Apptainer 이미지 빌드 (${STEP1_MIN}분)
  ✅ Step 2: Slurm QoS 생성 (${STEP2_ELAPSED}초)
  ✅ Step 3: Nginx 설정 적용 (${STEP3_ELAPSED}초)

========================================
다음 단계
========================================

1. Backend 시작 확인:
   lsof -i :8004

2. API 테스트:
   curl -k https://110.15.177.120/api/moonlight/images

3. 세션 생성 테스트:
   curl -X POST -k https://110.15.177.120/api/moonlight/sessions \\
        -H "Content-Type: application/json" \\
        -H "X-Username: testuser" \\
        -d '{"image_id": "desktop"}'

4. Frontend 개발 시작
5. WebRTC Signaling Server 구현 (Port 8005)

========================================
문서 참조
========================================

- 전체 구현 계획: IMPLEMENTATION_PLAN.md
- 배포 가이드: DEPLOYMENT_GUIDE.md
- 시스템 격리 감사: COMPLETE_SYSTEM_ISOLATION_AUDIT.md
- 문제 해결: IMPLEMENTATION_STATUS.md

========================================

EOF

log_success "Moonlight/Sunshine 시스템이 성공적으로 배포되었습니다!"
log_info ""
log_info "배포 완료 시각: $(date)"
log_info ""
