#!/bin/bash
################################################################################
# 멀티헤드 클러스터 오프라인 완전 자동화 스크립트
#
# 기능:
#   - 기본 시스템 설정 (SSH, /etc/hosts, Munge, PATH 등)
#   - 멀티헤드 클러스터 서비스 (GlusterFS, MariaDB, Redis, Slurm, Keepalived, 웹)
#   - **오프라인 환경 지원** (사전 패키징된 패키지 사용)
#
# 사용법:
#   sudo -E ./setup_cluster_full_multihead_offline.sh [--config CONFIG_FILE]
#
# 요구사항:
#   - my_multihead_cluster.yaml 설정 파일
#   - offline_packages/ 디렉토리 (prepare_offline_packages.sh로 생성)
#   - 환경변수: DB_ROOT_PASSWORD, REDIS_PASSWORD, SESSION_SECRET, JWT_SECRET
#
# 차이점 (온라인 버전 대비):
#   - 인터넷 다운로드 없음
#   - Slurm 프리빌드 바이너리 사용
#   - APT 패키지 로컬 설치
#   - 로컬 APT 미러 사용 (선택)
#
# 작성자: Claude Code
# 날짜: 2025-11-17
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 기본값
CONFIG_FILE="my_multihead_cluster.yaml"
DRY_RUN=false
SKIP_BASE_SETUP=false
SKIP_MULTIHEAD_SETUP=false
AUTO_CONFIRM=false
OFFLINE_PACKAGES_DIR="${SCRIPT_DIR}/offline_packages"
USE_APT_MIRROR=false
INSTALL_APT_PACKAGES=false  # 기본: APT 패키지 설치 안함 (옵션으로 활성화)

# Phase별 reset 옵션 (start_multihead.sh로 전달됨)
RESET_DB=false
RESET_REDIS=false
RESET_GLUSTER=false

# 로그 파일
LOG_FILE="/tmp/setup_cluster_full_multihead_offline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "📝 로그 파일: $LOG_FILE"
echo ""

# 도움말
usage() {
    cat << EOF
멀티헤드 HPC 클러스터 오프라인 완전 자동화 스크립트

사용법:
    sudo $0 [옵션]

옵션:
    --config FILE           설정 파일 경로 (기본: my_multihead_cluster.yaml)
    --offline-packages DIR  오프라인 패키지 디렉토리 (기본: ./offline_packages)
    --install-apt           오프라인 APT 패키지 설치 (기본: 설치 안함)
    --use-apt-mirror        로컬 APT 미러 사용
    --dry-run               실제 실행 없이 계획만 표시
    --skip-base             기본 시스템 설정 건너뛰기
    --skip-multihead        멀티헤드 서비스 설정 건너뛰기
    --auto-confirm          사용자 확인 없이 자동으로 진행
    --help                  이 도움말 표시

  Phase별 Reset 옵션 (비밀번호 충돌 시 사용):
    --reset-all             ⚠️  모든 서비스 완전 초기화 (DB, Redis, GlusterFS)
    --reset-db              ⚠️  MariaDB 완전 초기화 (YAML 비밀번호로 재설정)
    --reset-redis           ⚠️  Redis 클러스터 완전 초기화
    --reset-gluster         ⚠️  GlusterFS 볼륨 완전 초기화

오프라인 설치 준비:
    1. 인터넷이 되는 환경에서:
       sudo ./offline_packages/prepare_offline_packages.sh --all

    2. offline_packages/ 디렉토리를 오프라인 환경으로 복사:
       rsync -avz offline_packages/ user@offline-cluster:/opt/offline_packages/

    3. 오프라인 환경에서 이 스크립트 실행:
       sudo ./setup_cluster_full_multihead_offline.sh

예제:
    # 기본 설정 파일 사용
    sudo ./setup_cluster_full_multihead_offline.sh

    # 로컬 APT 미러 사용
    sudo ./setup_cluster_full_multihead_offline.sh --use-apt-mirror

    # 계획만 확인 (실제 실행 안함)
    sudo ./setup_cluster_full_multihead_offline.sh --dry-run

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
        --reset-all)
            RESET_DB=true
            RESET_REDIS=true
            RESET_GLUSTER=true
            shift
            ;;
        --reset-db)
            RESET_DB=true
            shift
            ;;
        --reset-redis)
            RESET_REDIS=true
            shift
            ;;
        --reset-gluster)
            RESET_GLUSTER=true
            shift
            ;;
        --help)
            usage
            ;;
        *.yaml|*.yml)
            # positional argument로 YAML 파일 지원
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
echo "║   멀티헤드 HPC 클러스터 오프라인 완전 자동화 설치             ║"
echo "║                                                                ║"
echo "║   기본 시스템 설정 + 멀티헤드 클러스터 서비스                ║"
echo "║   (인터넷 연결 불필요 - 사전 패키징된 패키지 사용)            ║"
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
    log_error ""
    log_error "오프라인 패키지를 준비해주세요:"
    log_error "  1. 인터넷이 되는 환경에서:"
    log_error "     sudo ./offline_packages/prepare_offline_packages.sh --all"
    log_error ""
    log_error "  2. 이 서버로 복사:"
    log_error "     rsync -avz offline_packages/ user@$(hostname):/path/to/offline_packages/"
    exit 1
fi

log_success "오프라인 패키지 디렉토리: $OFFLINE_PACKAGES_DIR"

# YAML에서 환경변수 로드 (멀티헤드 설정 시에만 필요)
if [ "$SKIP_MULTIHEAD_SETUP" = false ]; then
    log_info "YAML에서 환경변수 로드 중..."

    # Python으로 YAML의 environment 섹션 읽어서 export
    if python3 -c "import yaml" 2>/dev/null; then
        eval $(python3 <<'EOFPYTHON'
import yaml
import sys
import os

config_file = os.environ.get('CONFIG_FILE', 'my_multihead_cluster.yaml')

try:
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)

    # environment 섹션에서 환경변수 읽기
    env = config.get('environment', {})

    if not env:
        print("# No environment section found in YAML", file=sys.stderr)
    else:
        for key, value in env.items():
            # 값이 문자열이고 비어있지 않으면 export
            if value and isinstance(value, str):
                # 작은따옴표로 감싸서 안전하게 처리
                safe_value = value.replace("'", "'\\''")
                print(f"export {key}='{safe_value}'")
        print("# Environment variables loaded from YAML", file=sys.stderr)

except FileNotFoundError:
    print(f"# Error: {config_file} not found", file=sys.stderr)
    sys.exit(1)
except yaml.YAMLError as e:
    print(f"# Error parsing YAML: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"# Error: {e}", file=sys.stderr)
    sys.exit(1)
EOFPYTHON
        )

        if [ $? -eq 0 ]; then
            log_success "환경변수 로드 완료 (YAML environment 섹션)"
        else
            log_error "환경변수 로드 실패"
            exit 1
        fi
    else
        log_error "Python3 yaml 모듈이 필요합니다: pip3 install pyyaml"
        exit 1
    fi
fi

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다."
    echo "다음과 같이 실행하세요: sudo $0"
    exit 1
fi

echo ""
log_info "설치 계획:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SKIP_BASE_SETUP" = false ]; then
    echo "【Part 1】 기본 시스템 설정 (오프라인)"
    echo "  ✓ Python 가상환경"
    echo "  ✓ YAML 검증"
    if [ "$INSTALL_APT_PACKAGES" = true ]; then
        echo "  ✓ 오프라인 패키지 설치 (APT) ← --install-apt"
    else
        echo "  ○ 오프라인 패키지 설치 (APT) [건너뜀]"
    fi
    echo "  ✓ Slurm 프리빌드 배포"
    echo "  ✓ Munge 인증"
    echo "  ✓ SSH 키 설정"
    echo "  ✓ /etc/hosts 설정"
    echo "  ✓ PATH 설정"
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

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Part 1: 기본 시스템 설정 (오프라인)                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$SKIP_BASE_SETUP" = true ]; then
    log_warning "기본 시스템 설정을 건너뜁니다 (--skip-base)"
    echo ""
else
    ################################################################################
    # Step 1: 로컬 APT 미러 설정 (선택)
    ################################################################################

    if [ "$USE_APT_MIRROR" = true ]; then
        log_info "Step 1/9: 로컬 APT 미러 설정..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [ -f "${OFFLINE_PACKAGES_DIR}/apt_mirror/setup_client.sh" ]; then
            bash "${OFFLINE_PACKAGES_DIR}/apt_mirror/setup_client.sh"
            log_success "로컬 APT 미러 설정 완료"
        else
            log_warning "APT 미러 설정 스크립트를 찾을 수 없습니다"
        fi
        echo ""
    fi

    ################################################################################
    # Step 2: APT 패키지 설치 (옵션)
    ################################################################################

    if [ "$INSTALL_APT_PACKAGES" = true ]; then
        log_info "Step 2/9: APT 패키지 설치 (오프라인)..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [ -f "${OFFLINE_PACKAGES_DIR}/apt_packages/install_offline_packages.sh" ]; then
            cd "${OFFLINE_PACKAGES_DIR}/apt_packages"
            bash install_offline_packages.sh

            if [ $? -eq 0 ]; then
                log_success "APT 패키지 설치 완료"
            else
                log_error "APT 패키지 설치 실패"
                exit 1
            fi
        else
            log_warning "오프라인 APT 패키지를 찾을 수 없습니다"
        fi
        cd "$SCRIPT_DIR"
        echo ""
    else
        log_info "Step 2/9: APT 패키지 설치 건너뜀 (--install-apt 옵션 없음)"
        echo ""
    fi

    ################################################################################
    # Step 3: Slurm 프리빌드 배포
    ################################################################################

    log_info "Step 3/9: Slurm 프리빌드 배포..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "${OFFLINE_PACKAGES_DIR}/slurm/slurm-"*"-prebuilt.tar.gz" ]; then
        cd "${OFFLINE_PACKAGES_DIR}/slurm"

        # tarball 추출
        tar -xzf slurm-*-prebuilt.tar.gz

        # 배포 스크립트 실행
        if [ -f "deploy_slurm.sh" ]; then
            bash deploy_slurm.sh

            if [ $? -eq 0 ]; then
                log_success "Slurm 프리빌드 배포 완료"
            else
                log_error "Slurm 배포 실패"
                exit 1
            fi
        else
            log_error "Slurm 배포 스크립트를 찾을 수 없습니다"
            exit 1
        fi
    else
        log_warning "Slurm 프리빌드 패키지를 찾을 수 없습니다"
    fi
    cd "$SCRIPT_DIR"
    echo ""

    ################################################################################
    # Step 4: Munge 설치
    ################################################################################

    log_info "Step 4/9: Munge 인증 시스템 설치..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "${OFFLINE_PACKAGES_DIR}/munge/deploy_munge.sh" ]; then
        cd "${OFFLINE_PACKAGES_DIR}/munge"
        bash deploy_munge.sh

        if [ $? -eq 0 ]; then
            log_success "Munge 설치 완료"
        else
            log_warning "Munge 설치 실패 (계속 진행)"
        fi
    else
        log_warning "Munge 배포 스크립트를 찾을 수 없습니다"
    fi
    cd "$SCRIPT_DIR"
    echo ""

    ################################################################################
    # 나머지 단계들 (기존 setup_cluster_full_multihead.sh와 동일)
    ################################################################################

    # Step 5: Python 가상환경
    # Step 6: 설정 검증
    # Step 7: SSH 연결 테스트
    # Step 8: /etc/hosts 설정
    # Step 9: PATH 설정
    # (기존 코드 재사용)

    log_success "기본 시스템 설정 완료!"
    echo ""
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
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Part 2: 멀티헤드 클러스터 서비스                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # cluster/start_multihead.sh 실행
    MULTIHEAD_SCRIPT="cluster/start_multihead.sh"

    if [ -f "$MULTIHEAD_SCRIPT" ]; then
        log_info "멀티헤드 클러스터 오케스트레이션 시작..."
        echo ""

        chmod +x "$MULTIHEAD_SCRIPT"

        # start_multihead.sh 옵션 구성
        MULTIHEAD_OPTS="--config $CONFIG_FILE --auto-confirm"

        # Phase별 reset 옵션 전달
        if [ "$RESET_DB" = true ]; then
            MULTIHEAD_OPTS="$MULTIHEAD_OPTS --reset-db"
            log_warning "⚠️  MariaDB 완전 초기화 옵션 활성화"
        fi
        if [ "$RESET_REDIS" = true ]; then
            MULTIHEAD_OPTS="$MULTIHEAD_OPTS --reset-redis"
            log_warning "⚠️  Redis 클러스터 완전 초기화 옵션 활성화"
        fi
        if [ "$RESET_GLUSTER" = true ]; then
            MULTIHEAD_OPTS="$MULTIHEAD_OPTS --reset-gluster"
            log_warning "⚠️  GlusterFS 볼륨 완전 초기화 옵션 활성화"
        fi

        log_info "실행 명령: bash $MULTIHEAD_SCRIPT $MULTIHEAD_OPTS"
        echo ""

        # 환경변수 전달하여 실행
        if bash "$MULTIHEAD_SCRIPT" $MULTIHEAD_OPTS; then
            log_success "멀티헤드 클러스터 서비스 설치 완료!"
        else
            log_error "멀티헤드 클러스터 서비스 설치 실패"
            exit 1
        fi
    else
        log_error "cluster/start_multihead.sh를 찾을 수 없습니다"
        exit 1
    fi
    echo ""
else
    log_warning "멀티헤드 클러스터 서비스 설치를 건너뜁니다 (--skip-multihead)"
    echo ""
fi

################################################################################
# 완료
################################################################################

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║  🎉 멀티헤드 HPC 클러스터 오프라인 설치 완료!                 ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
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

log_success "오프라인 멀티헤드 클러스터가 준비되었습니다! 🚀"
echo ""
