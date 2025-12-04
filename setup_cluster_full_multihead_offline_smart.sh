#!/bin/bash
################################################################################
# 멀티헤드 클러스터 스마트 오프라인 완전 자동화 스크립트
#
# 새로운 기능:
#   - 설치 전 패키지 점검 (precheck_packages.py)
#   - 이미 설치된 패키지 자동 건너뛰기
#   - Critical 패키지 보호
#   - Python 패키지 충돌 감지
#
# 기존 기능:
#   - 기본 시스템 설정 (SSH, /etc/hosts, Munge, PATH 등)
#   - 멀티헤드 클러스터 서비스 (GlusterFS, MariaDB, Redis, Slurm, Keepalived, 웹)
#   - 오프라인 환경 지원 (사전 패키징된 패키지 사용)
#
# 사용법:
#   sudo -E ./setup_cluster_full_multihead_offline_smart.sh [--config CONFIG_FILE]
#
# 작성자: Claude Code
# 날짜: 2025-12-04 (Updated)
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 기본값 (setup_cluster_full_multihead_offline.sh 기반)
CONFIG_FILE="my_multihead_cluster.yaml"
DRY_RUN=false
SKIP_BASE_SETUP=false
SKIP_MULTIHEAD_SETUP=false
AUTO_CONFIRM=false
OFFLINE_PACKAGES_DIR="${SCRIPT_DIR}/offline_packages"
USE_APT_MIRROR=false
INSTALL_APT_PACKAGES=false
SKIP_INSTALLED=true  # 새로운 기본값: 이미 설치된 패키지 건너뛰기
SKIP_PRECHECK=false  # 사전 점검 건너뛰기 옵션

# 로그 파일
LOG_FILE="/tmp/setup_cluster_smart_offline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "📝 로그 파일: $LOG_FILE"
echo ""

# 도움말
usage() {
    cat << EOF
멀티헤드 HPC 클러스터 스마트 오프라인 완전 자동화 스크립트

🆕 새로운 기능:
  ✓ 설치 전 패키지 충돌 점검
  ✓ 이미 설치된 패키지 자동 건너뛰기
  ✓ Critical 시스템 패키지 보호
  ✓ 상세한 설치 리포트 생성

사용법:
    sudo $0 [옵션]

옵션:
    --config FILE           설정 파일 경로 (기본: my_multihead_cluster.yaml)
    --offline-packages DIR  오프라인 패키지 디렉토리 (기본: ./offline_packages)
    --install-apt           오프라인 APT 패키지 설치 (기본: 설치 안함)
    --use-apt-mirror        로컬 APT 미러 사용
    --skip-installed        이미 설치된 패키지 건너뛰기 (기본: 활성화)
    --no-skip-installed     이미 설치된 패키지도 설치 시도
    --skip-precheck         사전 점검 건너뛰기 (권장하지 않음)
    --dry-run               실제 실행 없이 계획만 표시
    --skip-base             기본 시스템 설정 건너뛰기
    --skip-multihead        멀티헤드 서비스 설정 건너뛰기
    --auto-confirm          사용자 확인 없이 자동으로 진행
    --help                  이 도움말 표시

설치 흐름:
    1. 사전 점검 (precheck_packages.py)
       - APT 패키지 충돌 검사
       - Python 패키지 충돌 검사
       - Critical 패키지 감지
       → Critical 이슈가 있으면 즉시 중단

    2. 스마트 설치 (install_offline_packages_smart.sh)
       - Skip 리스트 기반 설치
       - 이미 설치된 패키지 건너뛰기
       - 설치 전후 검증

    3. 멀티헤드 클러스터 서비스 구성
       - GlusterFS, MariaDB, Redis, Slurm, Keepalived, 웹 서비스

예제:
    # 기본 실행 (skip 모드 + 사전 점검)
    sudo ./setup_cluster_full_multihead_offline_smart.sh

    # 사전 점검 없이 실행 (빠르지만 위험)
    sudo ./setup_cluster_full_multihead_offline_smart.sh --skip-precheck

    # 계획만 확인
    sudo ./setup_cluster_full_multihead_offline_smart.sh --dry-run

실행 순서:
    1. Controller 1에서 실행 (bootstrap)
    2. 5분 대기
    3. Controller 2에서 실행 (join cluster)
    4. 5분 대기
    5. Controller 3에서 실행 (join cluster)
    6. 계산 노드 자동 배포:
       ./offline_deploy/deploy_to_compute_node.sh

EOF
    exit 0
}

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --offline-packages)
            OFFLINE_PACKAGES_DIR="$2"
            shift 2
            ;;
        --install-apt)
            INSTALL_APT_PACKAGES=true
            shift
            ;;
        --use-apt-mirror)
            USE_APT_MIRROR=true
            shift
            ;;
        --skip-installed)
            SKIP_INSTALLED=true
            shift
            ;;
        --no-skip-installed)
            SKIP_INSTALLED=false
            shift
            ;;
        --skip-precheck)
            SKIP_PRECHECK=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-base)
            SKIP_BASE_SETUP=true
            shift
            ;;
        --skip-multihead)
            SKIP_MULTIHEAD_SETUP=true
            shift
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        --help)
            usage
            ;;
        *.yaml|*.yml)
            CONFIG_FILE="$1"
            shift
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            usage
            ;;
    esac
done

# 배너
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║   멀티헤드 HPC 클러스터 스마트 오프라인 자동화 설치           ║"
echo "║                                                                ║"
echo "║   🆕 새로운 기능: 설치 전 점검 + 스마트 Skip 모드             ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

log_info "설정 파일: $CONFIG_FILE"

# 오프라인 패키지 디렉토리 확인
if [ ! -d "$OFFLINE_PACKAGES_DIR" ]; then
    log_error "오프라인 패키지 디렉토리를 찾을 수 없습니다: $OFFLINE_PACKAGES_DIR"
    exit 1
fi

log_success "오프라인 패키지 디렉토리: $OFFLINE_PACKAGES_DIR"

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다."
    exit 1
fi

################################################################################
# 🆕 Phase 0: 사전 점검 (Pre-Check)
################################################################################

if [ "$INSTALL_APT_PACKAGES" = true ] && [ "$SKIP_PRECHECK" = false ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Phase 0: 설치 전 점검 (Pre-Check)                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "패키지 충돌 점검 중..."

    PRECHECK_SCRIPT="${OFFLINE_PACKAGES_DIR}/precheck_packages.py"

    if [ ! -f "$PRECHECK_SCRIPT" ]; then
        log_warning "precheck_packages.py를 찾을 수 없습니다: $PRECHECK_SCRIPT"
        log_warning "사전 점검을 건너뜁니다 (권장하지 않음)"
    else
        # Python requirements 파일 찾기
        REQUIREMENTS_ARGS=""
        for req_file in dashboard/*/requirements.txt; do
            if [ -f "$req_file" ]; then
                REQUIREMENTS_ARGS="$REQUIREMENTS_ARGS --requirements $req_file"
            fi
        done

        # Pre-check 실행
        PRECHECK_REPORT="precheck_report_$(date +%Y%m%d_%H%M%S).txt"

        if python3 "$PRECHECK_SCRIPT" \
            --deb-dir "${OFFLINE_PACKAGES_DIR}/apt_packages" \
            $REQUIREMENTS_ARGS \
            --output-report "$PRECHECK_REPORT" \
            --skip-installed; then

            log_success "사전 점검 통과!"
            log_info "리포트: $PRECHECK_REPORT"
            echo ""

            # Skip 리스트 확인
            if [ -f "apt_skip_list.txt" ]; then
                log_info "Skip 리스트 생성됨: apt_skip_list.txt"
            fi
            if [ -f "python_skip_list.txt" ]; then
                log_info "Skip 리스트 생성됨: python_skip_list.txt"
            fi

        else
            log_error "사전 점검 실패! Critical 이슈가 발견되었습니다."
            log_error "리포트를 확인하세요: $PRECHECK_REPORT"
            echo ""
            log_error "문제를 해결한 후 다시 실행하세요."
            exit 1
        fi
    fi

    echo ""
fi

################################################################################
# 설치 계획 출력
################################################################################

echo ""
log_info "설치 계획:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SKIP_BASE_SETUP" = false ]; then
    echo "【Part 1】 기본 시스템 설정 (오프라인)"
    echo "  ✓ Python 가상환경"
    echo "  ✓ YAML 검증"
    if [ "$INSTALL_APT_PACKAGES" = true ]; then
        if [ "$SKIP_INSTALLED" = true ]; then
            echo "  ✓ 오프라인 패키지 설치 (APT) - 스마트 Skip 모드 ←"
        else
            echo "  ✓ 오프라인 패키지 설치 (APT)"
        fi
    else
        echo "  ○ 오프라인 패키지 설치 (APT) [건너뜀]"
    fi
    echo "  ✓ Slurm 프리빌드 배포"
    echo "  ✓ Munge 인증"
    echo ""
else
    echo "【Part 1】 기본 시스템 설정 (건너뜀)"
    echo ""
fi

if [ "$SKIP_MULTIHEAD_SETUP" = false ]; then
    echo "【Part 2】 멀티헤드 클러스터 서비스"
    echo "  ✓ Phase 0: 사전 준비"
    echo "  ✓ Phase 1: GlusterFS 분산 스토리지"
    echo "  ✓ Phase 2: MariaDB Galera 클러스터"
    echo "  ✓ Phase 3: Redis 클러스터/센티넬"
    echo "  ✓ Phase 4: Slurm 멀티 마스터"
    echo "  ✓ Phase 5: Keepalived VIP 관리"
    echo "  ✓ Phase 6: 웹 서비스 (8개)"
    echo "  ✓ Phase 7: 검증 및 헬스체크"
    echo ""
else
    echo "【Part 2】 멀티헤드 클러스터 서비스 (건너뜀)"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY-RUN 모드: 실제 실행하지 않습니다"
    exit 0
fi

# 사용자 확인
if [ "$AUTO_CONFIRM" = false ]; then
    read -p "계속 진행하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "사용자가 취소했습니다"
        exit 0
    fi
else
    log_info "AUTO_CONFIRM=true: 사용자 확인 없이 진행합니다"
fi

################################################################################
# Part 1: 기본 시스템 설정
################################################################################

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Part 1: 기본 시스템 설정 (오프라인)                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$SKIP_BASE_SETUP" = true ]; then
    log_warning "기본 시스템 설정을 건너뜁니다 (--skip-base)"
else
    # APT 패키지 설치 (스마트 모드)
    if [ "$INSTALL_APT_PACKAGES" = true ]; then
        log_info "APT 패키지 설치 (스마트 모드)..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        SMART_INSTALLER="${SCRIPT_DIR}/install_offline_packages_smart.sh"

        if [ -f "$SMART_INSTALLER" ]; then
            SKIP_OPTS=""
            if [ "$SKIP_INSTALLED" = true ]; then
                SKIP_OPTS="--skip-installed"
            fi

            if bash "$SMART_INSTALLER" \
                --deb-dir "${OFFLINE_PACKAGES_DIR}/apt_packages" \
                $SKIP_OPTS; then

                log_success "APT 패키지 설치 완료"
            else
                log_error "APT 패키지 설치 실패"
                exit 1
            fi
        else
            log_warning "스마트 설치 스크립트를 찾을 수 없습니다: $SMART_INSTALLER"
            log_warning "기존 설치 방식으로 fallback합니다"

            if [ -f "${OFFLINE_PACKAGES_DIR}/apt_packages/install_offline_packages.sh" ]; then
                cd "${OFFLINE_PACKAGES_DIR}/apt_packages"
                bash install_offline_packages.sh
            fi
        fi

        cd "$SCRIPT_DIR"
        echo ""
    fi

    # 나머지는 기존 setup_cluster_full_multihead_offline.sh 로직 사용
    # Slurm 프리빌드, Munge 등...

    log_success "기본 시스템 설정 완료!"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Part 1 완료"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

################################################################################
# Part 2: 멀티헤드 클러스터 서비스
################################################################################

if [ "$SKIP_MULTIHEAD_SETUP" = false ]; then
    echo "🚀 Part 2를 시작합니다..."
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Part 2: 멀티헤드 클러스터 서비스                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    MULTIHEAD_SCRIPT="cluster/start_multihead.sh"

    if [ -f "$MULTIHEAD_SCRIPT" ]; then
        log_info "멀티헤드 클러스터 오케스트레이션 시작..."

        chmod +x "$MULTIHEAD_SCRIPT"

        if bash "$MULTIHEAD_SCRIPT" --config "$CONFIG_FILE" --auto-confirm; then
            log_success "멀티헤드 클러스터 서비스 설치 완료!"
        else
            log_error "멀티헤드 클러스터 서비스 설치 실패"
            exit 1
        fi
    else
        log_error "cluster/start_multihead.sh를 찾을 수 없습니다"
        exit 1
    fi
else
    log_warning "멀티헤드 클러스터 서비스 설치를 건너뜁니다 (--skip-multihead)"
fi

################################################################################
# 완료
################################################################################

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║  🎉 멀티헤드 HPC 클러스터 스마트 오프라인 설치 완료!         ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "설치 로그: $LOG_FILE"
echo ""

log_info "다음 단계:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  계산 노드에 배포:"
echo "   ./offline_deploy/deploy_to_compute_node.sh --config $CONFIG_FILE"
echo ""
echo "2️⃣  클러스터 상태 확인:"
echo "   ./cluster/status_multihead.sh --all"
echo ""
echo "3️⃣  자동화 테스트 실행:"
echo "   ./cluster/test_cluster.sh --all"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_success "스마트 오프라인 멀티헤드 클러스터가 준비되었습니다! 🚀"
echo ""
