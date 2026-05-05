#!/bin/bash
################################################################################
# 24.04 오프라인 패키지 통합 복원 스크립트
#
# 처음부터 끝까지 한 번의 명령으로 모든 패키지/빌드 결과 복원:
#   1. KVM 24.04 VM 생성 (없으면)
#   2. APT 패키지 수집 (호스트 클론 + 27 카테고리 + 과학계산/시각화)
#   3. Python wheels 다운로드 (6개 대시보드 서비스)
#   4. Slurm 23.11.10 소스 빌드 → prebuilt tarball
#   5. OpenCASCADE 7.7.0 소스 빌드 → tarball
#   6. 외부 .deb 다운로드 (Grafana, Chrome, VSCode, Sunshine)
#   7. NVIDIA 드라이버 + CUDA .run 다운로드
#   8. 모든 결과 호스트로 sync
#   9. md5 검증
#
# 사용법:
#   sudo ./restore_all.sh [OPTIONS]
#
# 옵션:
#   --fresh                  새 VM 생성 (기존 VM 폐기)
#   --keep-vm                작업 후 VM 유지 (기본: 정리)
#   --skip-occt              OpenCASCADE 빌드 스킵
#   --skip-external          외부 다운로드 스킵
#   --skip-wheels            Python wheels 스킵
#   --only-occt              OpenCASCADE만 (다른 단계 모두 스킵)
#   --only-external          외부 다운로드만
#   --yes                    모든 확인 자동 yes
#
# 예상 소요 시간:
#   --fresh 전체: 4~6시간
#   기존 VM 재사용: 2~3시간
#   --only-occt: 30~60분
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}══════ $1 ══════${NC}"; }

# 옵션
FRESH_VM=false
KEEP_VM=false
SKIP_OCCT=false
SKIP_EXTERNAL=false
SKIP_WHEELS=false
ONLY_OCCT=false
ONLY_EXTERNAL=false
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh)         FRESH_VM=true; shift ;;
        --keep-vm)       KEEP_VM=true; shift ;;
        --skip-occt)     SKIP_OCCT=true; shift ;;
        --skip-external) SKIP_EXTERNAL=true; shift ;;
        --skip-wheels)   SKIP_WHEELS=true; shift ;;
        --only-occt)     ONLY_OCCT=true; shift ;;
        --only-external) ONLY_EXTERNAL=true; shift ;;
        --yes|-y)        AUTO_YES=true; shift ;;
        --help|-h)
            head -35 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

[[ $EUID -ne 0 ]] && { log_error "root 필요 (sudo)"; exit 1; }

# 환경 검증
log_step "환경 검증"
for cmd in virsh virt-install qemu-img wget rsync ssh ssh-keygen sshpass openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "필수 명령어 없음: $cmd"
        exit 1
    fi
done
log_success "필수 도구 OK"

# 디스크 여유 (최소 30GB)
AVAIL_GB=$(df --output=avail -BG "$SCRIPT_DIR" | tail -1 | tr -dc '0-9')
if (( AVAIL_GB < 30 )); then
    log_error "디스크 여유 부족: ${AVAIL_GB}GB (최소 30GB 필요)"
    exit 1
fi
log_success "디스크 여유: ${AVAIL_GB}GB"

# 사용자 SSH 키 확인 (VM 통신용)
if [[ ! -f /home/koopark/.ssh/id_rsa ]]; then
    log_error "SSH 키 없음: /home/koopark/.ssh/id_rsa"
    exit 1
fi
log_success "SSH 키 OK"

############################
# Phase A: APT + Python wheels + Slurm 빌드 (prepare 스크립트)
############################
if [[ "$ONLY_OCCT" == "false" && "$ONLY_EXTERNAL" == "false" ]]; then
    log_step "Phase A: APT + Python + Slurm (prepare_offline_packages_2404.sh)"

    PREPARE_ARGS=()
    [[ "$AUTO_YES" == "true" ]] && PREPARE_ARGS+=(--yes)
    [[ "$KEEP_VM" == "true" ]] && PREPARE_ARGS+=(--skip-vm-cleanup)
    [[ "$FRESH_VM" == "false" ]] && PREPARE_ARGS+=(--reuse-vm)

    if [[ "$SKIP_WHEELS" == "true" ]]; then
        log_warning "Python wheels 스킵 (--skip-wheels)"
    fi

    bash "$SCRIPT_DIR/prepare_offline_packages_2404.sh" "${PREPARE_ARGS[@]}"
    log_success "Phase A 완료"
else
    log_warning "Phase A 스킵"
fi

############################
# Phase B: OpenCASCADE 7.7.0 빌드
############################
if [[ "$ONLY_EXTERNAL" == "false" && "$SKIP_OCCT" == "false" ]]; then
    log_step "Phase B: OpenCASCADE 7.7.0 빌드"

    OCCT_TARBALL="$SCRIPT_DIR/opencascade/opencascade-7.7.0-noble-prebuilt.tar.gz"

    if [[ -f "$OCCT_TARBALL" ]] && [[ "$AUTO_YES" == "true" ]]; then
        log_info "기존 OCCT tarball 발견: $OCCT_TARBALL ($(du -h $OCCT_TARBALL | cut -f1))"
        log_info "재빌드 스킵 (재빌드하려면 파일 삭제 후 재실행)"
    else
        # VM IP 찾기
        VM_IP=$(virsh domifaddr noble-pkg-collector 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d'/' -f1)
        if [[ -z "$VM_IP" ]]; then
            log_error "VM이 실행 중이 아님 — Phase A 먼저 실행 필요"
            exit 1
        fi

        # 빌드 스크립트 전송
        scp -i /home/koopark/.ssh/id_rsa -o StrictHostKeyChecking=no \
            "$SCRIPT_DIR/opencascade/build_opencascade_2404.sh" \
            ubuntu@"$VM_IP":/tmp/

        # VM에서 빌드
        ssh -i /home/koopark/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@"$VM_IP" \
            "sudo bash /tmp/build_opencascade_2404.sh"

        # 결과 호스트로 sync
        mkdir -p "$SCRIPT_DIR/opencascade"
        scp -i /home/koopark/.ssh/id_rsa -o StrictHostKeyChecking=no \
            ubuntu@"$VM_IP":/home/ubuntu/opencascade-7.7.0-noble-prebuilt.tar.gz \
            ubuntu@"$VM_IP":/home/ubuntu/opencascade-7.7.0-noble-prebuilt.tar.gz.md5 \
            "$SCRIPT_DIR/opencascade/"

        # md5 파일 경로 정리
        sed -i 's|/home/ubuntu/||' "$SCRIPT_DIR/opencascade/opencascade-7.7.0-noble-prebuilt.tar.gz.md5"

        # 검증
        cd "$SCRIPT_DIR/opencascade"
        if md5sum -c opencascade-7.7.0-noble-prebuilt.tar.gz.md5; then
            log_success "OCCT 빌드 + 검증 완료"
        else
            log_error "OCCT md5 검증 실패!"
            exit 1
        fi
    fi
else
    log_warning "Phase B (OCCT) 스킵"
fi

############################
# Phase C: 외부 .deb / .run 다운로드
############################
if [[ "$ONLY_OCCT" == "false" && "$SKIP_EXTERNAL" == "false" ]]; then
    log_step "Phase C: 외부 패키지 다운로드 (Grafana/Chrome/VSCode/NVIDIA/CUDA/Sunshine)"

    EXT_ARGS=(--all --skip-existing)
    bash "$SCRIPT_DIR/download_external_packages.sh" "${EXT_ARGS[@]}"
    log_success "Phase C 완료"
else
    log_warning "Phase C (외부) 스킵"
fi

############################
# 최종 검증
############################
log_step "최종 검증"

APT=$(ls "$SCRIPT_DIR/apt_packages"/*.deb 2>/dev/null | wc -l)
WHL=$(find "$SCRIPT_DIR/python_wheels" -name "*.whl" 2>/dev/null | wc -l)
SLURM_TAR=$([[ -f "$SCRIPT_DIR/slurm/slurm-23.11.10-prebuilt.tar.gz" ]] && echo "✅" || echo "❌")
OCCT_TAR=$([[ -f "$SCRIPT_DIR/opencascade/opencascade-7.7.0-noble-prebuilt.tar.gz" ]] && echo "✅" || echo "❌")
NVIDIA=$(ls "$SCRIPT_DIR/gpu/nvidia"/NVIDIA-Linux-x86_64-*.run 2>/dev/null | wc -l)
CUDA=$(ls "$SCRIPT_DIR/gpu/nvidia"/cuda_*.run 2>/dev/null | wc -l)
GRAFANA=$([[ -f "$SCRIPT_DIR/apt_packages/grafana_"*.deb ]] && echo "✅" || echo "❌")
CHROME=$([[ -f "$SCRIPT_DIR/apt_packages/google-chrome-stable_current_amd64.deb" ]] && echo "✅" || echo "❌")
VSCODE=$([[ -f "$SCRIPT_DIR/apt_packages/code_latest_amd64.deb" ]] && echo "✅" || echo "❌")
SUNSHINE=$([[ -f "$SCRIPT_DIR/apt_packages/sunshine-ubuntu-24.04-amd64.deb" ]] && echo "✅" || echo "❌")
TOTAL=$(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)

cat <<EOF

╔══════════════════════════════════════════════╗
║   24.04 오프라인 패키지 복원 완료 요약        ║
╠══════════════════════════════════════════════╣
║  APT .deb:           ${APT}개
║  Python wheels:      ${WHL}개
║  Slurm prebuilt:     ${SLURM_TAR}
║  OpenCASCADE 7.7.0:  ${OCCT_TAR}
║  NVIDIA 드라이버:    ${NVIDIA}개 .run
║  CUDA Toolkit:       ${CUDA}개 .run
║  Grafana:            ${GRAFANA}
║  Chrome:             ${CHROME}
║  VSCode:             ${VSCODE}
║  Sunshine:           ${SUNSHINE}
║  ────────────────────────────────────────
║  전체 크기:          ${TOTAL}
╚══════════════════════════════════════════════╝

다음 단계:
  1. 백업/전송:    docs/BACKUP_TRANSFER_GUIDE.md 참조
  2. 오프라인 설치: docs/INSTALL_GUIDE_346.md 참조
EOF

log_success "복원 완료!"
