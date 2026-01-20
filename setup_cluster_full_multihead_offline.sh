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

# Phase 시작 옵션 (start_multihead.sh로 전달됨)
START_PHASE=""

# 로그 파일 (현재 디렉토리의 setup.log + 타임스탬프 백업)
LOG_FILE="${SCRIPT_DIR}/setup.log"
LOG_FILE_TIMESTAMPED="${SCRIPT_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"

# 기존 setup.log가 있으면 백업
if [[ -f "$LOG_FILE" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak"
fi

# stdout/stderr를 tee로 파일과 터미널 모두에 출력
exec > >(tee "$LOG_FILE" | tee "$LOG_FILE_TIMESTAMPED")
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
    --skip-base             기본 시스템 설정 건너뛰기 (Slurm/Munge 설치 스킵)
    --skip-multihead        멀티헤드 서비스 설정 건너뛰기
    --start-phase N         특정 Phase부터 시작 (0-9, 예: --start-phase 6 = 웹 서비스부터)
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

    # 웹 서비스(Phase 6)만 실행 (Slurm 등 기본 설정 스킵)
    sudo ./setup_cluster_full_multihead_offline.sh --start-phase 6

Phase 번호 참조:
    0=infrastructure, 1=storage, 2=database, 3=redis, 4=slurm
    5=keepalived, 6=web, 7=backup, 8=containers, 9=software

실행 순서:
    1. Controller 1에서 실행 (bootstrap)
    2. 5분 대기
    3. Controller 2에서 실행 (join cluster)
    4. 5분 대기
    5. Controller 3에서 실행 (join cluster)
    6. 계산 노드 자동 배포:
       ./offline_deploy/deploy_to_compute_node.sh

Bootstrap 모드란?
    클러스터의 첫 번째 노드를 초기화하는 모드입니다.

    자동 판단 기준:
    - GlusterFS: 기존 볼륨이 없으면 → bootstrap (새 볼륨 생성)
    - MariaDB Galera: 기존 클러스터 없으면 → bootstrap (gcomm://)
    - 첫 컨트롤러는 보통 bootstrap 모드로 실행됨

    Bootstrap 모드에서만 실행되는 작업:
    - GlusterFS 볼륨 생성 (새 클러스터)
    - MariaDB root 비밀번호 초기 설정
    - Slurm 데이터베이스 스키마 생성

    모든 모드에서 실행되는 작업:
    - /shared/logs, /shared/jobs 디렉토리 생성 ✅
    - Slurm 설정 파일 생성
    - 웹 서비스 배포

    단일 노드 환경:
    - 첫 실행은 자동으로 bootstrap 모드
    - 재실행 시 기존 서비스에 조인 시도
    - 문제 발생 시 --reset-* 옵션 사용

주의사항:
    - YAML 파일에 민감 정보가 포함되므로 권한 설정 필요:
      chmod 600 my_multihead_cluster.yaml

    - Git 저장소에 커밋 시 주의 (.gitignore 권장)

    - 오프라인 패키지 디렉토리도 보안 주의:
      chmod 700 offline_packages/

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
        --start-phase)
            START_PHASE="$2"
            SKIP_BASE_SETUP=true  # Phase 지정 시 기본 설정도 스킵
            shift 2
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

    # SSO 설정 환경변수 추가 (Dashboard 서비스용)
    sso_config = config.get('sso', {})
    sso_enabled = sso_config.get('enabled', True)
    print(f"export SSO_ENABLED={'true' if sso_enabled else 'false'}")
    print(f"# SSO_ENABLED={sso_enabled} (from YAML sso.enabled)", file=sys.stderr)

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
    echo "  ✓ systemd 서비스 파일"
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
    echo "  ✓ Phase 7: GPU 드라이버 (NVIDIA/ROCm)"
    echo "  ✓ Phase 8: 컨테이너 이미지 배포"
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
        log_info "Step 1/10: 로컬 APT 미러 설정..."
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
    # Step 2: Slurm 프리빌드 배포 (APT 패키지보다 먼저!)
    # 소스 빌드 Slurm을 먼저 배포해야 APT 패키지 설치 시 slurm 관련 패키지를 건너뜀
    ################################################################################

    log_info "Step 2/10: Slurm 프리빌드 배포..."
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

        # Slurm 배포 후 즉시 PATH 적용 (hash 테이블 갱신)
        if [ -f "/etc/profile.d/slurm.sh" ]; then
            source /etc/profile.d/slurm.sh 2>/dev/null || true
            hash -r 2>/dev/null || true
            log_info "PATH 적용됨: $(which sinfo 2>/dev/null || echo 'sinfo not found')"
        fi
    else
        log_warning "Slurm 프리빌드 패키지를 찾을 수 없습니다"
    fi
    cd "$SCRIPT_DIR"
    echo ""

    ################################################################################
    # Step 3: APT 패키지 설치 (옵션) - Slurm 배포 이후에 실행
    # 소스 빌드 Slurm이 이미 배포되어 있으므로 slurm 관련 apt 패키지는 건너뜀
    ################################################################################

    if [ "$INSTALL_APT_PACKAGES" = true ]; then
        log_info "Step 3/10: APT 패키지 설치 (오프라인)..."
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
        log_info "Step 3/10: APT 패키지 설치 건너뜀 (--install-apt 옵션 없음)"
        echo ""
    fi

    ################################################################################
    # Step 4: Munge 설치
    ################################################################################

    log_info "Step 4/10: Munge 인증 시스템 설치..."
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
    # Step 5: Python 가상환경
    ################################################################################

    log_info "Step 5/10: Python 가상환경 확인..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -d "venv" ]; then
        log_warning "가상환경이 없습니다. 생성합니다..."
        python3 -m venv venv
    fi

    source venv/bin/activate
    log_success "가상환경 활성화 완료"
    echo ""

    ################################################################################
    # Step 6: 설정 검증
    ################################################################################

    log_info "Step 6/10: 설정 파일 검증..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "cluster/config/parser.py" ]; then
        python3 cluster/config/parser.py "$CONFIG_FILE" validate
        if [ $? -ne 0 ]; then
            log_error "설정 파일 검증 실패"
            exit 1
        fi
        log_success "설정 파일 검증 완료"
    else
        log_warning "parser.py가 없습니다. 건너뜁니다."
    fi
    echo ""

    ################################################################################
    # Step 7: SSH 연결 테스트 및 자동 설정
    ################################################################################

    log_info "Step 7/10: SSH 연결 테스트 및 자동 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 멀티헤드 환경에서는 모든 컨트롤러 간 SSH 키 필요
    log_info "멀티헤드 환경: 모든 컨트롤러 간 SSH 키 설정 필요"

    # 실제 사용자 (sudo로 실행 시 SUDO_USER, 아니면 현재 사용자)
    SETUP_USER="${SUDO_USER:-$(whoami)}"
    SETUP_USER_HOME=$(getent passwd "$SETUP_USER" | cut -d: -f6)
    SETUP_SSH_DIR="${SETUP_USER_HOME}/.ssh"
    SETUP_SSH_KEY="${SETUP_SSH_DIR}/id_rsa"

    log_info "SSH 설정 사용자: $SETUP_USER (홈: $SETUP_USER_HOME)"

    # .ssh 디렉토리가 없으면 생성
    if [ ! -d "$SETUP_SSH_DIR" ]; then
        log_info ".ssh 디렉토리 생성 중..."
        mkdir -p "$SETUP_SSH_DIR"
        chown "$SETUP_USER:$SETUP_USER" "$SETUP_SSH_DIR"
        chmod 700 "$SETUP_SSH_DIR"
    fi

    # SSH 키가 없으면 생성 (기존 키가 있으면 삭제 후 재생성 - 권한 문제 방지)
    if [ ! -f "$SETUP_SSH_KEY" ]; then
        log_info "SSH 키 생성 중..."
        # 기존에 손상된 키 파일이 있으면 삭제
        rm -f "$SETUP_SSH_KEY" "$SETUP_SSH_KEY.pub" 2>/dev/null || true
        # 실제 사용자로 SSH 키 생성
        sudo -u "$SETUP_USER" ssh-keygen -t rsa -b 4096 -N "" -f "$SETUP_SSH_KEY"
        log_success "SSH 키 생성 완료: $SETUP_SSH_KEY"
    else
        # 기존 키 소유권 확인 및 수정 (소유자가 SETUP_USER가 아니면 수정)
        KEY_OWNER=$(stat -c '%U' "$SETUP_SSH_KEY" 2>/dev/null)
        if [ "$KEY_OWNER" != "$SETUP_USER" ]; then
            log_warning "SSH 키 소유자가 $KEY_OWNER입니다. $SETUP_USER로 변경 중..."
            chown "$SETUP_USER:$SETUP_USER" "$SETUP_SSH_KEY" "$SETUP_SSH_KEY.pub" 2>/dev/null || true
            chmod 600 "$SETUP_SSH_KEY" 2>/dev/null || true
            chmod 644 "$SETUP_SSH_KEY.pub" 2>/dev/null || true
            log_success "SSH 키 소유권 수정 완료"
        fi
        log_success "SSH 키가 이미 존재합니다: $SETUP_SSH_KEY"
    fi

    # setup_ssh_passwordless_multihead.sh 실행 (멀티헤드용)
    if [ -f "setup_ssh_passwordless_multihead.sh" ]; then
        log_info "SSH 키 자동 배포 중..."
        chmod +x setup_ssh_passwordless_multihead.sh
        if ./setup_ssh_passwordless_multihead.sh "$CONFIG_FILE"; then
            log_success "SSH 키 배포 완료"
        else
            log_warning "SSH 키 자동 배포 실패"
            echo ""
            echo "⚠️  일부 노드는 비밀번호 입력이 필요할 수 있습니다."
            echo "   설치를 계속하시려면 각 노드에 접속할 때 비밀번호를 입력하세요."
            echo ""
            if [ "$AUTO_CONFIRM" = false ]; then
                read -p "계속하시겠습니까? (Y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Nn]$ ]]; then
                    exit 1
                fi
            fi
        fi
    else
        log_warning "setup_ssh_passwordless_multihead.sh가 없습니다"
        echo "⚠️  SSH 키 설정을 수동으로 해야 할 수 있습니다"
    fi

    log_success "SSH 설정 완료"
    echo ""

    ################################################################################
    # Step 8: /etc/hosts 자동 설정
    ################################################################################

    log_info "Step 8/10: /etc/hosts 자동 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 멀티헤드 환경: 모든 노드 추가 (컨트롤러 + 컴퓨트)
    if [ -f "cluster/config/parser.py" ]; then
        log_info "YAML에서 모든 노드 정보 추출 중..."

        # 컨트롤러 목록 추출
        log_info "컨트롤러 노드 추가 중..."
        mapfile -t CONTROLLERS < <(python3 cluster/config/parser.py "$CONFIG_FILE" get-controllers | tail -n +2)

        for ctrl_line in "${CONTROLLERS[@]}"; do
            # 형식: hostname|ip_address|...
            hostname=$(echo "$ctrl_line" | cut -d'|' -f1)
            ip_addr=$(echo "$ctrl_line" | cut -d'|' -f2)

            if ! grep -q "$hostname" /etc/hosts; then
                log_info "  $hostname ($ip_addr) 추가 중..."
                echo "$ip_addr $hostname" | sudo tee -a /etc/hosts > /dev/null
            else
                log_success "  $hostname 이미 존재함"
            fi
        done

        # 컴퓨트 노드 목록 추출
        log_info "컴퓨트 노드 추가 중..."
        mapfile -t COMPUTE_NODES < <(python3 cluster/config/parser.py "$CONFIG_FILE" get-nodes | tail -n +2)

        for node_line in "${COMPUTE_NODES[@]}"; do
            # 형식: hostname|ip_address|...
            hostname=$(echo "$node_line" | cut -d'|' -f1)
            ip_addr=$(echo "$node_line" | cut -d'|' -f2)

            if [[ -n "$hostname" && -n "$ip_addr" ]]; then
                if ! grep -q "$hostname" /etc/hosts; then
                    log_info "  $hostname ($ip_addr) 추가 중..."
                    echo "$ip_addr $hostname" | sudo tee -a /etc/hosts > /dev/null
                else
                    log_success "  $hostname 이미 존재함"
                fi
            fi
        done

        log_success "/etc/hosts 설정 완료 (컨트롤러 + 컴퓨트 노드)"
    else
        log_warning "parser.py가 없습니다. 수동으로 /etc/hosts를 설정하세요"
    fi
    echo ""

    ################################################################################
    # Step 9: systemd 서비스 파일 생성
    ################################################################################

    log_info "Step 9/10: systemd 서비스 파일 생성..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "create_slurm_systemd_services.sh" ]; then
        chmod +x create_slurm_systemd_services.sh
        sudo bash create_slurm_systemd_services.sh

        if [ $? -eq 0 ]; then
            log_success "systemd 서비스 파일 생성 완료"
        else
            log_warning "systemd 서비스 파일 생성 실패 (계속 진행)"
        fi
    else
        log_warning "create_slurm_systemd_services.sh를 찾을 수 없습니다"
    fi
    echo ""

    ################################################################################
    # Step 10: PATH 영구 설정
    ################################################################################

    log_info "Step 10/10: PATH 영구 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # /etc/profile.d/slurm.sh 내용 확인 및 생성/업데이트
    SLURM_PROFILE="/etc/profile.d/slurm.sh"
    NEED_UPDATE=false

    if [ ! -f "$SLURM_PROFILE" ]; then
        NEED_UPDATE=true
        log_info "$SLURM_PROFILE 파일이 없음 - 생성 필요"
    elif ! grep -q "^export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin" "$SLURM_PROFILE" 2>/dev/null; then
        NEED_UPDATE=true
        log_warning "$SLURM_PROFILE에 올바른 PATH 설정이 없음 - 업데이트 필요"
    fi

    if [ "$NEED_UPDATE" = true ]; then
        log_info "$SLURM_PROFILE 생성/업데이트 중..."
        sudo tee "$SLURM_PROFILE" > /dev/null << 'SLURM_PATH_EOF'
# Slurm Environment (소스 빌드 Slurm 23.x 우선)
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:$MANPATH}
SLURM_PATH_EOF
        sudo chmod 644 "$SLURM_PROFILE"
        log_success "$SLURM_PROFILE 생성/업데이트 완료"
    else
        log_success "$SLURM_PROFILE 이미 올바르게 설정됨"
    fi

    # 현재 터미널에 PATH 적용 (앞에 추가)
    source "$SLURM_PROFILE" 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH

    # PATH 적용 확인
    if command -v /usr/local/slurm/bin/sinfo &>/dev/null; then
        SINFO_VERSION=$(/usr/local/slurm/bin/sinfo --version 2>/dev/null || echo "알 수 없음")
        log_success "PATH 적용 완료: $SINFO_VERSION"
    else
        log_warning "PATH 적용됨 (Slurm 바이너리 확인 필요)"
    fi
    echo ""

    log_success "기본 시스템 설정 완료!"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Part 1 완료"
echo "📋 SKIP_MULTIHEAD_SETUP = $SKIP_MULTIHEAD_SETUP"
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

    echo "🔍 디버그 정보:"
    echo "  - 스크립트 경로: $MULTIHEAD_SCRIPT"
    echo "  - 파일 존재 여부: $([ -f "$MULTIHEAD_SCRIPT" ] && echo "✅ YES" || echo "❌ NO")"
    echo "  - 설정 파일: $CONFIG_FILE"
    echo "  - 현재 EUID: $EUID"
    echo "  - 현재 USER: $USER"
    echo ""

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

        # Phase 시작 옵션 전달
        if [ -n "$START_PHASE" ]; then
            MULTIHEAD_OPTS="$MULTIHEAD_OPTS --phase $START_PHASE"
            log_info "📌 Phase $START_PHASE 부터 시작합니다"
        fi

        echo "🚀 실행 명령: bash $MULTIHEAD_SCRIPT $MULTIHEAD_OPTS"
        echo ""

        # sudo 중첩 방지: 이미 root면 sudo 없이, 아니면 sudo 사용
        if [ "$EUID" -eq 0 ]; then
            bash "$MULTIHEAD_SCRIPT" $MULTIHEAD_OPTS
            RESULT=$?
        else
            sudo -E bash "$MULTIHEAD_SCRIPT" $MULTIHEAD_OPTS
            RESULT=$?
        fi

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Part 2 실행 결과: $RESULT"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        if [ $RESULT -eq 0 ]; then
            log_success "멀티헤드 클러스터 서비스 설치 완료!"
        else
            log_error "멀티헤드 클러스터 서비스 설치 실패 (종료 코드: $RESULT)"
            exit 1
        fi
    else
        log_error "cluster/start_multihead.sh를 찾을 수 없습니다"
        log_error "현재 디렉토리: $(pwd)"
        log_error "파일 목록:"
        ls -la cluster/ 2>&1 | head -10
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

################################################################################
# Part 3: 컴퓨트 노드 자동 배포
################################################################################

DEPLOY_COMPUTE_SCRIPT="offline_deploy/deploy_to_compute_node.sh"

if [ -f "$DEPLOY_COMPUTE_SCRIPT" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Part 3: 컴퓨트 노드 자동 배포                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "컴퓨트 노드에 Slurm 패키지 배포 중..."
    log_info "  - slurm.conf 자동 복사 (컨트롤러 → 컴퓨트)"
    log_info "  - PluginDir 자동 수정"
    log_info "  - slurmd 서비스 자동 시작"
    echo ""

    chmod +x "$DEPLOY_COMPUTE_SCRIPT"

    if bash "$DEPLOY_COMPUTE_SCRIPT" --config "$CONFIG_FILE" --yes; then
        log_success "컴퓨트 노드 배포 완료!"
    else
        log_warning "일부 컴퓨트 노드 배포 실패 (수동 확인 필요)"
        log_info "수동 재시도: ./offline_deploy/deploy_to_compute_node.sh --config $CONFIG_FILE"
    fi
    echo ""
else
    log_warning "컴퓨트 노드 배포 스크립트를 찾을 수 없습니다: $DEPLOY_COMPUTE_SCRIPT"
    log_info "수동 배포: ./offline_deploy/deploy_to_compute_node.sh --config $CONFIG_FILE"
fi

log_info "다음 단계:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  (자동 완료) 계산 노드 배포"
echo "   재시도: ./offline_deploy/deploy_to_compute_node.sh --config $CONFIG_FILE"
echo ""
echo "2️⃣  클러스터 상태 확인:"
echo "   ./cluster/status_multihead.sh --all"
echo ""
echo "3️⃣  자동화 테스트 실행:"
echo "   ./cluster/test_cluster.sh --all"
echo ""
echo "4️⃣  웹 서비스 헬스체크:"
echo "   ./cluster/utils/web_health_check.sh"
echo ""
echo "5️⃣  클러스터 중지:"
echo "   ./cluster/stop_multihead.sh"
echo ""
echo "6️⃣  Slurm 명령어:"
echo "   sinfo              # 클러스터 상태"
echo "   squeue             # 작업 큐"
echo "   sbatch test.sh     # 작업 제출"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "설치된 서비스:"
echo "  ✅ GlusterFS 분산 스토리지"
echo "  ✅ MariaDB Galera 클러스터"
echo "  ✅ Redis 클러스터/센티넬"
echo "  ✅ Slurm 멀티 마스터"
echo "  ✅ Keepalived VIP"
echo "  ✅ 웹 서비스 (8개)"
echo ""

log_success "오프라인 멀티헤드 클러스터가 준비되었습니다! 🚀"
echo ""
