#!/bin/bash
# ========================================================================
# Moonlight/Sunshine Apptainer 이미지 빌드 스크립트 (Step 1)
# ========================================================================
# 목적: viz-node에서 3개 Sunshine 이미지 빌드
# 위치: viz-node001에서 실행
# 권한: sudo 필요
# 소요시간: 60-90분 (from-scratch) 또는 30-40분 (VNC 재사용)
# ========================================================================

set -e  # 에러 발생 시 즉시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# ========================================================================
# 1. 환경 확인
# ========================================================================

log_info "Step 1: 환경 확인 시작"

# 현재 노드 확인
HOSTNAME=$(hostname)
log_info "현재 노드: $HOSTNAME"

if [[ ! "$HOSTNAME" =~ viz-node ]]; then
    log_warn "⚠️  현재 노드가 viz-node가 아닙니다: $HOSTNAME"
    log_warn "이 스크립트는 viz-node에서 실행해야 합니다 (NVIDIA GPU 필요)"
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "사용자가 취소했습니다"
        exit 1
    fi
fi

# NVIDIA GPU 확인
log_info "NVIDIA GPU 확인 중..."
if ! command -v nvidia-smi &> /dev/null; then
    log_error "nvidia-smi를 찾을 수 없습니다"
    log_error "이 노드에는 NVIDIA 드라이버가 설치되어 있지 않습니다"
    exit 1
fi

nvidia-smi &> /dev/null
if [ $? -ne 0 ]; then
    log_error "nvidia-smi 실행 실패"
    log_error "NVIDIA 드라이버가 제대로 설치되어 있지 않습니다"
    exit 1
fi

log_info "✅ NVIDIA GPU 확인 완료"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

# Apptainer 확인
log_info "Apptainer 설치 확인 중..."
if ! command -v apptainer &> /dev/null; then
    log_error "apptainer를 찾을 수 없습니다"
    log_error "Apptainer를 설치해주세요"
    exit 1
fi

APPTAINER_VERSION=$(apptainer --version)
log_info "✅ Apptainer 버전: $APPTAINER_VERSION"

# sudo 권한 확인
log_info "sudo 권한 확인 중..."
if ! sudo -n true 2>/dev/null; then
    log_warn "sudo 권한이 필요합니다"
    sudo -v
fi
log_info "✅ sudo 권한 확인 완료"

# ========================================================================
# 2. 빌드 전략 선택
# ========================================================================

log_info ""
log_info "Step 2: 빌드 전략 선택"
echo ""
echo "=========================================="
echo "Apptainer 이미지 빌드 전략 선택"
echo "=========================================="
echo ""
echo "1) From-scratch 빌드 (권장)"
echo "   - 소요시간: 60-90분"
echo "   - 장점: 깨끗한 구성, 최신 패키지"
echo "   - 스크립트: build_sunshine_images.sh"
echo ""
echo "2) VNC 이미지 재사용"
echo "   - 소요시간: 30-40분"
echo "   - 장점: 빠름, 기존 환경 재사용"
echo "   - 스크립트: build_from_vnc_images.sh"
echo ""
read -p "빌드 전략을 선택하세요 (1 or 2): " -n 1 -r
echo ""

BUILD_STRATEGY=""
BUILD_SCRIPT=""

if [[ $REPLY == "1" ]]; then
    BUILD_STRATEGY="from-scratch"
    BUILD_SCRIPT="build_sunshine_images.sh"
    log_info "선택: From-scratch 빌드 (예상 60-90분)"
elif [[ $REPLY == "2" ]]; then
    BUILD_STRATEGY="vnc-reuse"
    BUILD_SCRIPT="build_from_vnc_images.sh"
    log_info "선택: VNC 이미지 재사용 (예상 30-40분)"
else
    log_error "잘못된 선택입니다: $REPLY"
    exit 1
fi

# ========================================================================
# 3. 빌드 스크립트 및 Definition 파일 복사
# ========================================================================

log_info ""
log_info "Step 3: 빌드 파일 준비"

# 작업 디렉토리 생성
WORK_DIR="/tmp/sunshine_build_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log_info "작업 디렉토리: $WORK_DIR"

# Controller에서 파일 복사 (이미 viz-node라면 직접 복사)
SOURCE_DIR="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004"

if [ -d "$SOURCE_DIR" ]; then
    log_info "Controller의 파일 복사 중..."
    cp "$SOURCE_DIR/$BUILD_SCRIPT" .

    if [ "$BUILD_STRATEGY" == "from-scratch" ]; then
        cp "$SOURCE_DIR/sunshine_desktop.def" .
        cp "$SOURCE_DIR/sunshine_gnome.def" .
        cp "$SOURCE_DIR/sunshine_gnome_lsprepost.def" .
    fi

    chmod +x "$BUILD_SCRIPT"
    log_info "✅ 파일 복사 완료"
else
    log_error "소스 디렉토리를 찾을 수 없습니다: $SOURCE_DIR"
    log_error "파일을 수동으로 복사해주세요"
    exit 1
fi

# ========================================================================
# 4. 빌드 실행
# ========================================================================

log_info ""
log_info "Step 4: 이미지 빌드 시작"
log_info "=========================================="

# 빌드 시작 시각
START_TIME=$(date +%s)
log_info "빌드 시작: $(date)"

# 빌드 실행
log_info "실행 중: sudo bash $BUILD_SCRIPT"
echo ""

if sudo bash "$BUILD_SCRIPT"; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))

    log_info ""
    log_info "=========================================="
    log_info "✅ 이미지 빌드 성공!"
    log_info "소요시간: ${ELAPSED_MIN}분 (${ELAPSED}초)"
    log_info "=========================================="
else
    log_error ""
    log_error "=========================================="
    log_error "❌ 이미지 빌드 실패"
    log_error "로그를 확인하세요: $WORK_DIR"
    log_error "=========================================="
    exit 1
fi

# ========================================================================
# 5. 빌드된 이미지 확인
# ========================================================================

log_info ""
log_info "Step 5: 빌드된 이미지 확인"

IMAGES_BUILT=0

if [ -f "sunshine_desktop.sif" ]; then
    SIZE=$(du -h sunshine_desktop.sif | cut -f1)
    log_info "✅ sunshine_desktop.sif ($SIZE)"
    IMAGES_BUILT=$((IMAGES_BUILT + 1))
else
    log_warn "⚠️  sunshine_desktop.sif 없음"
fi

if [ -f "sunshine_gnome.sif" ]; then
    SIZE=$(du -h sunshine_gnome.sif | cut -f1)
    log_info "✅ sunshine_gnome.sif ($SIZE)"
    IMAGES_BUILT=$((IMAGES_BUILT + 1))
else
    log_warn "⚠️  sunshine_gnome.sif 없음"
fi

if [ -f "sunshine_gnome_lsprepost.sif" ]; then
    SIZE=$(du -h sunshine_gnome_lsprepost.sif | cut -f1)
    log_info "✅ sunshine_gnome_lsprepost.sif ($SIZE)"
    IMAGES_BUILT=$((IMAGES_BUILT + 1))
else
    log_warn "⚠️  sunshine_gnome_lsprepost.sif 없음"
fi

if [ $IMAGES_BUILT -eq 0 ]; then
    log_error "빌드된 이미지가 없습니다"
    exit 1
fi

log_info "빌드 완료: $IMAGES_BUILT/3 개 이미지"

# ========================================================================
# 6. 이미지 검증
# ========================================================================

log_info ""
log_info "Step 6: 이미지 검증"

for IMAGE in sunshine_desktop.sif sunshine_gnome.sif sunshine_gnome_lsprepost.sif; do
    if [ -f "$IMAGE" ]; then
        log_info "검증 중: $IMAGE"

        # GPU 접근 테스트
        if apptainer exec --nv "$IMAGE" nvidia-smi &> /dev/null; then
            log_info "  ✅ GPU 접근 성공"
        else
            log_warn "  ⚠️  GPU 접근 실패 (하지만 계속 진행)"
        fi

        # Sunshine 버전 확인
        SUNSHINE_VERSION=$(apptainer exec "$IMAGE" sunshine --version 2>&1 | head -1 || echo "unknown")
        log_info "  ✅ Sunshine: $SUNSHINE_VERSION"
    fi
done

# ========================================================================
# 7. /opt/apptainers/로 복사
# ========================================================================

log_info ""
log_info "Step 7: 이미지를 /opt/apptainers/로 복사"

TARGET_DIR="/opt/apptainers"

if [ ! -d "$TARGET_DIR" ]; then
    log_warn "/opt/apptainers/ 디렉토리가 없습니다. 생성합니다..."
    sudo mkdir -p "$TARGET_DIR"
fi

for IMAGE in sunshine_desktop.sif sunshine_gnome.sif sunshine_gnome_lsprepost.sif; do
    if [ -f "$IMAGE" ]; then
        log_info "복사 중: $IMAGE → $TARGET_DIR/"
        sudo cp "$IMAGE" "$TARGET_DIR/"
        sudo chmod 755 "$TARGET_DIR/$IMAGE"
        sudo chown root:root "$TARGET_DIR/$IMAGE"
        log_info "  ✅ 복사 완료"
    fi
done

# 최종 확인
log_info ""
log_info "최종 이미지 목록:"
ls -lh "$TARGET_DIR"/sunshine_*.sif 2>/dev/null || log_warn "이미지를 찾을 수 없습니다"

# ========================================================================
# 8. 정리
# ========================================================================

log_info ""
log_info "Step 8: 작업 디렉토리 정리"
log_info "작업 디렉토리: $WORK_DIR"
read -p "작업 디렉토리를 삭제하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd /tmp
    rm -rf "$WORK_DIR"
    log_info "✅ 작업 디렉토리 삭제 완료"
else
    log_info "작업 디렉토리 유지: $WORK_DIR"
fi

# ========================================================================
# 완료
# ========================================================================

log_info ""
log_info "=========================================="
log_info "🎉 Step 1: Apptainer 이미지 빌드 완료!"
log_info "=========================================="
log_info ""
log_info "다음 단계:"
log_info "  1. Controller로 돌아가기"
log_info "  2. Step 2 실행: deploy_step2_create_qos.sh"
log_info "  3. Step 3 실행: deploy_step3_nginx.sh"
log_info ""
