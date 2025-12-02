#!/bin/bash
################################################################################
# 멀티헤드 클러스터 완전 자동화 스크립트
#
# 기능:
#   - 기본 시스템 설정 (SSH, /etc/hosts, Munge, PATH 등)
#   - 멀티헤드 클러스터 서비스 (GlusterFS, MariaDB, Redis, Slurm, Keepalived, 웹)
#
# 사용법:
#   sudo -E ./setup_cluster_full_multihead.sh [--config CONFIG_FILE]
#
# 요구사항:
#   - my_multihead_cluster.yaml 설정 파일
#   - 환경변수: DB_ROOT_PASSWORD, REDIS_PASSWORD, SESSION_SECRET, JWT_SECRET
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

# 로그 파일
LOG_FILE="/tmp/setup_cluster_full_multihead_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "📝 로그 파일: $LOG_FILE"
echo ""

# 도움말
usage() {
    cat << EOF
멀티헤드 HPC 클러스터 완전 자동화 스크립트

사용법:
    sudo $0 [옵션]

옵션:
    --config FILE           설정 파일 경로 (기본: my_multihead_cluster.yaml)
    --dry-run               실제 실행 없이 계획만 표시
    --skip-base             기본 시스템 설정 건너뛰기
    --skip-multihead        멀티헤드 서비스 설정 건너뛰기
    --auto-confirm          사용자 확인 없이 자동으로 진행
    --help                  이 도움말 표시

설정 방법:
    모든 설정은 YAML 파일에서 관리됩니다!

    1. my_multihead_cluster.yaml 편집:
       vim my_multihead_cluster.yaml

    2. environment 섹션에서 비밀번호 설정:
       environment:
         DB_SLURM_PASSWORD: "your_password"
         DB_AUTH_PASSWORD: "your_password"
         REDIS_PASSWORD: "your_password"
         JWT_SECRET_KEY: "your_jwt_secret"
         GRAFANA_PASSWORD: "your_grafana_password"

    3. 스크립트 실행 (환경변수 불필요!):
       sudo ./setup_cluster_full_multihead.sh

예제:
    # 기본 설정 파일 사용
    sudo ./setup_cluster_full_multihead.sh

    # 특정 설정 파일 사용
    sudo ./setup_cluster_full_multihead.sh --config custom.yaml

    # 멀티헤드 서비스만 설치 (기본 시스템은 이미 설정됨)
    sudo ./setup_cluster_full_multihead.sh --skip-base

    # 계획만 확인 (실제 실행 안함)
    sudo ./setup_cluster_full_multihead.sh --dry-run

실행 순서:
    1. Controller 1에서 실행 (bootstrap)
    2. 5분 대기
    3. Controller 2에서 실행 (join cluster)
    4. 5분 대기
    5. Controller 3에서 실행 (join cluster)

주의사항:
    - YAML 파일에 민감 정보가 포함되므로 권한 설정 필요:
      chmod 600 my_multihead_cluster.yaml

    - Git 저장소에 커밋 시 주의 (.gitignore 권장)

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
echo "║      멀티헤드 HPC 클러스터 완전 자동화 설치                   ║"
echo "║                                                                ║"
echo "║  기본 시스템 설정 + 멀티헤드 클러스터 서비스                 ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

log_info "설정 파일: $CONFIG_FILE"

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
    echo "【Part 1】 기본 시스템 설정"
    echo "  ✓ Python 가상환경"
    echo "  ✓ YAML 검증"
    echo "  ✓ SSH 키 설정"
    echo "  ✓ /etc/hosts 설정"
    echo "  ✓ Munge 인증"
    echo "  ✓ Slurm 기본 설치"
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
echo "║  Part 1: 기본 시스템 설정                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$SKIP_BASE_SETUP" = true ]; then
    log_warning "기본 시스템 설정을 건너뜁니다 (--skip-base)"
    echo ""
else
    ################################################################################
    # Step 1: Python 가상환경
    ################################################################################

    log_info "Step 1/8: Python 가상환경 확인..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -d "venv" ]; then
        log_warning "가상환경이 없습니다. 생성합니다..."
        python3 -m venv venv
    fi

    source venv/bin/activate
    log_success "가상환경 활성화 완료"
    echo ""

    ################################################################################
    # Step 2: 설정 검증
    ################################################################################

    log_info "Step 2/8: 설정 파일 검증..."
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
    # Step 3: SSH 연결 테스트 및 자동 설정
    ################################################################################

    log_info "Step 3/8: SSH 연결 테스트 및 자동 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 멀티헤드 환경에서는 모든 컨트롤러 간 SSH 키 필요
    log_info "멀티헤드 환경: 모든 컨트롤러 간 SSH 키 설정 필요"

    # SSH 키가 없으면 생성
    if [ ! -f ~/.ssh/id_rsa ]; then
        log_info "SSH 키 생성 중..."
        ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
        log_success "SSH 키 생성 완료"
    else
        log_success "SSH 키가 이미 존재합니다"
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
            read -p "계속하시겠습니까? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                exit 1
            fi
        fi
    else
        log_warning "setup_ssh_passwordless_multihead.sh가 없습니다"
        echo "⚠️  SSH 키 설정을 수동으로 해야 할 수 있습니다"
    fi

    log_success "SSH 설정 완료"
    echo ""

    ################################################################################
    # Step 4: /etc/hosts 자동 설정
    ################################################################################

    log_info "Step 4/8: /etc/hosts 자동 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 멀티헤드 환경: 모든 컨트롤러 추가
    if [ -f "cluster/config/parser.py" ]; then
        log_info "YAML에서 컨트롤러 정보 추출 중..."

        # 컨트롤러 목록 추출
        mapfile -t CONTROLLERS < <(python3 cluster/config/parser.py "$CONFIG_FILE" get-controllers | tail -n +2)

        for ctrl_line in "${CONTROLLERS[@]}"; do
            # 형식: hostname|ip_address|...
            hostname=$(echo "$ctrl_line" | cut -d'|' -f1)
            ip_addr=$(echo "$ctrl_line" | cut -d'|' -f2)

            if ! grep -q "$hostname" /etc/hosts; then
                log_info "$hostname ($ip_addr) 추가 중..."
                echo "$ip_addr $hostname" | sudo tee -a /etc/hosts > /dev/null
            else
                log_success "$hostname 이미 존재함"
            fi
        done

        log_success "/etc/hosts 설정 완료"
    else
        log_warning "parser.py가 없습니다. 수동으로 /etc/hosts를 설정하세요"
    fi
    echo ""

    ################################################################################
    # Step 5: Munge 설치
    ################################################################################

    log_info "Step 5/8: Munge 인증 시스템 설치..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "install_munge_auto.sh" ]; then
        chmod +x install_munge_auto.sh
        ./install_munge_auto.sh "$CONFIG_FILE"

        if [ $? -eq 0 ]; then
            log_success "Munge 자동 설치 완료"
        else
            log_warning "Munge 자동 설치 실패 (계속 진행)"
        fi
    else
        log_warning "install_munge_auto.sh가 없습니다"
    fi
    echo ""

    ################################################################################
    # Step 6: Slurm 기본 설치
    ################################################################################

    log_info "Step 6/8: Slurm 23.11.x + cgroup v2 설치..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "(시간이 걸릴 수 있습니다 - 약 15-20분)"
    echo ""

    if [ -f "install_slurm_cgroup_v2.sh" ]; then
        chmod +x install_slurm_cgroup_v2.sh
        sudo bash install_slurm_cgroup_v2.sh

        if [ $? -eq 0 ]; then
            log_success "Slurm 설치 완료"
        else
            log_error "Slurm 설치 실패"
            exit 1
        fi
    else
        log_warning "install_slurm_cgroup_v2.sh가 없습니다"
    fi
    echo ""

    ################################################################################
    # Step 7: systemd 서비스 파일 생성
    ################################################################################

    log_info "Step 7/8: systemd 서비스 파일 생성..."
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
    # Step 8: PATH 영구 설정
    ################################################################################

    log_info "Step 8/8: PATH 영구 설정..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # /etc/profile.d/slurm.sh 확인
    if [ ! -f "/etc/profile.d/slurm.sh" ]; then
        log_info "/etc/profile.d/slurm.sh 생성 중..."
        sudo tee /etc/profile.d/slurm.sh > /dev/null << 'SLURM_PATH_EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:$MANPATH}
SLURM_PATH_EOF
        sudo chmod 644 /etc/profile.d/slurm.sh
        log_success "/etc/profile.d/slurm.sh 생성 완료"
    else
        log_success "/etc/profile.d/slurm.sh 이미 존재함"
    fi

    # 현재 터미널에 PATH 적용
    source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
    log_success "PATH 적용 완료"
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

        # 환경변수 전달하여 실행
        echo "🚀 실행 명령: bash $MULTIHEAD_SCRIPT --config $CONFIG_FILE --auto-confirm"
        echo ""

        # sudo 중첩 방지: 이미 root면 sudo 없이, 아니면 sudo 사용
        if [ "$EUID" -eq 0 ]; then
            bash "$MULTIHEAD_SCRIPT" --config "$CONFIG_FILE" --auto-confirm
            RESULT=$?
        else
            sudo -E bash "$MULTIHEAD_SCRIPT" --config "$CONFIG_FILE" --auto-confirm
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
echo "║  🎉 멀티헤드 HPC 클러스터 설치 완료!                          ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "다음 단계:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  클러스터 상태 확인:"
echo "   ./cluster/status_multihead.sh --all"
echo ""
echo "2️⃣  자동화 테스트 실행:"
echo "   ./cluster/test_cluster.sh --all"
echo ""
echo "3️⃣  웹 서비스 헬스체크:"
echo "   ./cluster/utils/web_health_check.sh"
echo ""
echo "4️⃣  클러스터 중지:"
echo "   ./cluster/stop_multihead.sh"
echo ""
echo "5️⃣  Slurm 명령어:"
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

log_success "멀티헤드 클러스터가 준비되었습니다! 🚀"
echo ""
