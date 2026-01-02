#!/bin/bash
################################################################################
# Slurm 오프라인 배포 스크립트 (계산 노드에서 실행)
################################################################################

set -e

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="/opt/slurm"
CONFIG_DIR="/opt/slurm/etc"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Slurm 오프라인 배포                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Installing Slurm to: $INSTALL_PREFIX"

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# ============================================================================
# apt 패키지로 설치된 Slurm 서비스 중지 (21.08.5 -> 23.11.10 전환)
# ============================================================================
log_info "Checking for existing apt Slurm services..."

# apt Slurm 서비스 중지 (모든 Slurm 서비스 - apt 및 소스 빌드 모두)
for service in slurmctld slurmd slurmdbd; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_info "Stopping Slurm service: $service"
        systemctl stop "$service" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_info "Disabling Slurm service: $service"
        systemctl disable "$service" 2>/dev/null || true
    fi
done

# 프로세스가 완전히 종료될 때까지 대기 (Text file busy 에러 방지)
log_info "Waiting for Slurm processes to terminate..."
for proc in slurmctld slurmd slurmdbd; do
    # pkill로 남아있는 프로세스 강제 종료
    pkill -9 "$proc" 2>/dev/null || true
done
sleep 2  # 프로세스 완전 종료 대기

# 프로세스가 여전히 실행 중인지 확인
for proc in slurmctld slurmd slurmdbd; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        log_warning "$proc is still running, forcing termination..."
        pkill -9 "$proc" 2>/dev/null || true
        sleep 1
    fi
done

# apt Slurm 바이너리 존재 확인 및 경고
if [[ -f /usr/bin/sinfo ]]; then
    APT_VERSION=$(/usr/bin/sinfo --version 2>/dev/null | head -1 || echo "unknown")
    log_warning "Found apt Slurm at /usr/bin: $APT_VERSION"
    log_info "Source-built Slurm 23.11.10 will be used instead (/usr/local/slurm/bin)"
fi

# Slurm 사용자 생성
# NOTE: UID 64001 사용 - 일반 시스템 계정(1000~)과 충돌 방지
# 이미 존재하면 건너뜀 (phase3_slurm.sh에서 YAML 기반 UID로 먼저 생성됨)
log_info "Creating slurm user..."
if ! id slurm &>/dev/null; then
    # 64001 사용 (기본값), 충돌 시 자동 할당
    groupadd -g 64001 slurm 2>/dev/null || groupadd slurm 2>/dev/null || true
    useradd -u 64001 -g slurm -m -s /bin/bash slurm 2>/dev/null || useradd -g slurm -m -s /bin/bash slurm 2>/dev/null || true
    log_success "User 'slurm' created"
else
    log_info "User 'slurm' already exists (using existing UID: $(id -u slurm))"
fi

# 디렉토리 복사
# tar.gz 압축 해제 후 opt/slurm 디렉토리가 SCRIPT_DIR 안에 생성됨
log_info "Copying Slurm binaries..."
log_info "  Source: ${SCRIPT_DIR}/opt/slurm"
log_info "  Destination: $INSTALL_PREFIX"

if [[ -d "${SCRIPT_DIR}/opt/slurm" ]]; then
    # 기존 설치 정리 (깨끗한 상태에서 복사)
    if [[ -d "$INSTALL_PREFIX" ]]; then
        log_info "Cleaning existing installation at $INSTALL_PREFIX..."
        rm -rf "$INSTALL_PREFIX"
    fi
    mkdir -p "$INSTALL_PREFIX"
    cp -a "${SCRIPT_DIR}/opt/slurm"/* "$INSTALL_PREFIX/"
    log_success "Slurm binaries copied successfully"
    log_info "  Installed $(ls -1 ${INSTALL_PREFIX}/bin 2>/dev/null | wc -l) binaries in bin/"
    log_info "  Installed $(ls -1 ${INSTALL_PREFIX}/sbin 2>/dev/null | wc -l) binaries in sbin/"
else
    log_error "Source directory not found: ${SCRIPT_DIR}/opt/slurm"
    log_error "tar extraction may have failed. Contents of SCRIPT_DIR:"
    ls -la "$SCRIPT_DIR"
    exit 1
fi

# 심볼릭 링크 생성
log_info "Creating symbolic links..."
# 기존 /usr/local/slurm이 디렉토리나 심볼릭 링크로 존재하면 제거
if [[ -e /usr/local/slurm || -L /usr/local/slurm ]]; then
    rm -rf /usr/local/slurm
fi
ln -sf "$INSTALL_PREFIX" /usr/local/slurm

# /usr/local/bin에 주요 명령어 심볼릭 링크 생성 (시스템 전역 PATH에 포함)
# 이렇게 하면 /etc/profile.d 로드 없이도 모든 셸에서 slurm 명령어 사용 가능
log_info "Creating /usr/local/bin symlinks for system-wide access..."
for cmd in sinfo squeue sbatch scancel scontrol sacct sacctmgr srun salloc; do
    if [[ -x "/usr/local/slurm/bin/$cmd" ]]; then
        ln -sf "/usr/local/slurm/bin/$cmd" "/usr/local/bin/$cmd"
        log_info "  /usr/local/bin/$cmd -> /usr/local/slurm/bin/$cmd"
    fi
done
for cmd in slurmctld slurmd slurmdbd; do
    if [[ -x "/usr/local/slurm/sbin/$cmd" ]]; then
        ln -sf "/usr/local/slurm/sbin/$cmd" "/usr/local/sbin/$cmd"
        log_info "  /usr/local/sbin/$cmd -> /usr/local/slurm/sbin/$cmd"
    fi
done

# PATH 설정 (profile.d - 로그인 셸용, 환경변수 완전 설정)
log_info "Configuring PATH..."
tee /etc/profile.d/slurm.sh > /dev/null << 'EOFPATH'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:$MANPATH}
EOFPATH
chmod 644 /etc/profile.d/slurm.sh

# 디렉토리 생성
log_info "Creating Slurm directories..."
mkdir -p /var/log/slurm
mkdir -p /var/spool/slurm/{state,d}
mkdir -p "$CONFIG_DIR"

chown -R slurm:slurm /var/log/slurm /var/spool/slurm "$CONFIG_DIR"
chmod 755 /var/log/slurm /var/spool/slurm

# slurm.conf 호환성 설정 (심볼릭 링크 대신 복사 방식)
# Slurm 23.02+ 버전은 /etc/slurm과 /usr/local/slurm/etc 양쪽 모두 참조
# 해결: 두 경로에 동일한 설정 파일을 복사하여 동기화
log_info "Configuring slurm.conf compatibility (copy mode)..."

# 케이스 1: /etc/slurm/slurm.conf만 있고 $CONFIG_DIR/slurm.conf가 없는 경우
#          -> /etc/slurm/slurm.conf를 $CONFIG_DIR로 복사
if [[ -f /etc/slurm/slurm.conf && ! -f "$CONFIG_DIR/slurm.conf" ]]; then
    cp /etc/slurm/slurm.conf "$CONFIG_DIR/slurm.conf"
    chown slurm:slurm "$CONFIG_DIR/slurm.conf"
    log_success "Copied /etc/slurm/slurm.conf -> $CONFIG_DIR/slurm.conf"

# 케이스 2: $CONFIG_DIR/slurm.conf만 있고 /etc/slurm/slurm.conf가 없는 경우
#          -> $CONFIG_DIR/slurm.conf를 /etc/slurm으로 복사
elif [[ -f "$CONFIG_DIR/slurm.conf" && ! -f /etc/slurm/slurm.conf ]]; then
    mkdir -p /etc/slurm
    cp "$CONFIG_DIR/slurm.conf" /etc/slurm/slurm.conf
    chown slurm:slurm /etc/slurm/slurm.conf
    log_success "Copied $CONFIG_DIR/slurm.conf -> /etc/slurm/slurm.conf"

# 케이스 3: 두 파일 모두 존재하는 경우
#          -> NodeName 정의가 있는 파일을 우선 사용하여 양쪽에 복사
elif [[ -f /etc/slurm/slurm.conf && -f "$CONFIG_DIR/slurm.conf" ]]; then
    # NodeName 정의 유무 확인 (tr -d로 개행 제거)
    ETC_HAS_NODES=$(grep -c "^NodeName=" /etc/slurm/slurm.conf 2>/dev/null | tr -d '\n' || echo 0)
    CONFIG_HAS_NODES=$(grep -c "^NodeName=" "$CONFIG_DIR/slurm.conf" 2>/dev/null | tr -d '\n' || echo 0)

    if [[ "$CONFIG_HAS_NODES" -gt 0 && "$ETC_HAS_NODES" -eq 0 ]]; then
        # $CONFIG_DIR에 노드 정의가 있고 /etc/slurm에 없으면 -> $CONFIG_DIR을 /etc/slurm으로 복사
        log_warning "/etc/slurm/slurm.conf has no NodeName definitions"
        log_info "Backing up /etc/slurm/slurm.conf to /etc/slurm/slurm.conf.bak"
        mv /etc/slurm/slurm.conf /etc/slurm/slurm.conf.bak
        cp "$CONFIG_DIR/slurm.conf" /etc/slurm/slurm.conf
        chown slurm:slurm /etc/slurm/slurm.conf
        log_success "Copied $CONFIG_DIR/slurm.conf -> /etc/slurm/slurm.conf (has NodeName definitions)"
    elif [[ "$ETC_HAS_NODES" -gt 0 && "$CONFIG_HAS_NODES" -eq 0 ]]; then
        # /etc/slurm에 노드 정의가 있고 $CONFIG_DIR에 없으면 -> /etc/slurm을 $CONFIG_DIR로 복사
        log_info "Backing up $CONFIG_DIR/slurm.conf"
        mv "$CONFIG_DIR/slurm.conf" "$CONFIG_DIR/slurm.conf.bak"
        cp /etc/slurm/slurm.conf "$CONFIG_DIR/slurm.conf"
        chown slurm:slurm "$CONFIG_DIR/slurm.conf"
        log_success "Copied /etc/slurm/slurm.conf -> $CONFIG_DIR/slurm.conf (has NodeName definitions)"
    elif [[ "$ETC_HAS_NODES" -gt 0 && "$CONFIG_HAS_NODES" -gt 0 ]]; then
        log_success "Both config files have NodeName definitions"
    else
        # 둘 다 노드 정의가 없으면 경고
        log_warning "Neither config file has NodeName definitions!"
        log_info "Using $CONFIG_DIR/slurm.conf by default"
    fi
fi

# slurmdbd.conf도 동일하게 처리 (복사 방식)
if [[ -f /etc/slurm/slurmdbd.conf && ! -f "$CONFIG_DIR/slurmdbd.conf" ]]; then
    cp /etc/slurm/slurmdbd.conf "$CONFIG_DIR/slurmdbd.conf"
    chown slurm:slurm "$CONFIG_DIR/slurmdbd.conf"
    chmod 600 "$CONFIG_DIR/slurmdbd.conf"
    log_success "Copied /etc/slurm/slurmdbd.conf -> $CONFIG_DIR/slurmdbd.conf"
elif [[ -f "$CONFIG_DIR/slurmdbd.conf" && ! -f /etc/slurm/slurmdbd.conf ]]; then
    mkdir -p /etc/slurm
    cp "$CONFIG_DIR/slurmdbd.conf" /etc/slurm/slurmdbd.conf
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf
    log_success "Copied $CONFIG_DIR/slurmdbd.conf -> /etc/slurm/slurmdbd.conf"
fi

# 권한 설정
chown -R root:root "$INSTALL_PREFIX"
chown -R slurm:slurm "$CONFIG_DIR"

# ============================================================================
# 설치 검증 및 PATH 강제 적용
# ============================================================================
log_info "Verifying installation..."

# 심볼릭 링크 검증
if [[ -L /usr/local/slurm && -d /usr/local/slurm/bin ]]; then
    log_success "Symbolic link verified: /usr/local/slurm -> $(readlink -f /usr/local/slurm)"
else
    log_error "Symbolic link failed! /usr/local/slurm does not point to valid directory"
    exit 1
fi

# sinfo 바이너리 존재 확인
if [[ -x /usr/local/slurm/bin/sinfo ]]; then
    log_success "Slurm binary verified: /usr/local/slurm/bin/sinfo"
else
    log_error "Slurm binary not found: /usr/local/slurm/bin/sinfo"
    exit 1
fi

# 버전 확인
SLURM_VERSION=$(/usr/local/slurm/bin/sinfo --version 2>/dev/null || echo "unknown")
log_success "Slurm version: $SLURM_VERSION"

# 현재 셸 PATH 갱신 (hash 테이블 클리어)
hash -r 2>/dev/null || true

# PATH 적용 (현재 스크립트 실행 환경)
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH

# which sinfo 확인
WHICH_SINFO=$(which sinfo 2>/dev/null || echo "not found")
if [[ "$WHICH_SINFO" == "/usr/local/slurm/bin/sinfo" ]]; then
    log_success "which sinfo = $WHICH_SINFO (올바름)"
else
    log_warning "which sinfo = $WHICH_SINFO"
    log_info "새 터미널에서 'source /etc/profile.d/slurm.sh' 실행 필요"
fi

log_success "Slurm deployed successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 중요: PATH 적용 방법"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  새 터미널을 열거나 다음 명령 실행:"
echo "    source /etc/profile.d/slurm.sh"
echo ""
echo "  확인 방법:"
echo "    which sinfo   # /usr/local/slurm/bin/sinfo 출력 확인"
echo "    sinfo --version  # slurm 23.x 출력 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Next steps:"
echo "  1. Configure slurm.conf in: $CONFIG_DIR"
echo "  2. Setup Munge authentication"
echo "  3. Start services: slurmctld / slurmd"
echo ""
