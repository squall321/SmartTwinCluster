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
# slurmstepd는 잡 실행 시 slurmd가 fork하므로 반드시 같이 종료해야 함
log_info "Waiting for Slurm processes to terminate..."
for proc in slurmctld slurmd slurmdbd slurmstepd sackd; do
    # pkill로 남아있는 프로세스 강제 종료
    pkill -9 "$proc" 2>/dev/null || true
done
sleep 2  # 프로세스 완전 종료 대기

# 프로세스가 여전히 실행 중인지 확인
for proc in slurmctld slurmd slurmdbd slurmstepd sackd; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        log_warning "$proc is still running, forcing termination..."
        pkill -9 "$proc" 2>/dev/null || true
        sleep 1
    fi
done

# 기존 /opt/slurm 바이너리를 inode 분리(rename)로 안전하게 비움
# Text file busy 회피: 실행 중인 파일을 mv하면 inode가 분리되어 새 cp가 가능
if [[ -d "$INSTALL_PREFIX" ]]; then
    log_info "Renaming existing $INSTALL_PREFIX to *.old (Text file busy 회피)..."
    OLD_BACKUP="${INSTALL_PREFIX}.old.$(date +%s)"
    if mv "$INSTALL_PREFIX" "$OLD_BACKUP" 2>/dev/null; then
        log_info "기존 설치를 ${OLD_BACKUP}로 이동 (재부팅 후 수동 삭제 가능)"
    else
        log_warning "기존 디렉토리 이동 실패 — 개별 파일 rename 시도"
        # 실행 중인 .so/.bin 파일들을 .old로 rename (inode 분리)
        find "$INSTALL_PREFIX" -type f \( -name "slurm*" -o -name "*.so*" \) 2>/dev/null | while read f; do
            mv "$f" "${f}.old.$(date +%s)" 2>/dev/null || true
        done
    fi
fi

# apt Slurm 바이너리 존재 확인 및 경고
if [[ -f /usr/bin/sinfo ]]; then
    APT_VERSION=$(/usr/bin/sinfo --version 2>/dev/null | head -1 || echo "unknown")
    log_warning "Found apt Slurm at /usr/bin: $APT_VERSION"
    log_info "Source-built Slurm 23.11.10 will be used instead (/usr/local/slurm/bin)"
fi

# Slurm/Munge 사용자 UID/GID — 우선순위:
#   1. 환경변수 SLURM_UID/SLURM_GID/MUNGE_UID/MUNGE_GID (호출자가 export)
#   2. /etc/slurm-uid.conf (KEY=VALUE 형식)
#   3. 폴백 1001/1002 (yaml 표준값)
SLURM_UID="${SLURM_UID:-}"
SLURM_GID="${SLURM_GID:-}"
MUNGE_UID="${MUNGE_UID:-}"
MUNGE_GID="${MUNGE_GID:-}"
if [[ -z "$SLURM_UID" && -f /etc/slurm-uid.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/slurm-uid.conf
fi
SLURM_UID="${SLURM_UID:-1001}"
SLURM_GID="${SLURM_GID:-1001}"
MUNGE_UID="${MUNGE_UID:-1002}"
MUNGE_GID="${MUNGE_GID:-1002}"
log_info "Target UID/GID — slurm=$SLURM_UID:$SLURM_GID  munge=$MUNGE_UID:$MUNGE_GID"

ensure_service_user() {
    local name="$1" uid="$2" gid="$3" shell="$4"
    if id "$name" &>/dev/null; then
        local cur_uid cur_gid
        cur_uid=$(id -u "$name"); cur_gid=$(id -g "$name")
        if [[ "$cur_gid" != "$gid" ]]; then
            log_warning "$name GID 정렬: $cur_gid → $gid"
            groupmod -g "$gid" "$name" 2>/dev/null || true
            find / -xdev -gid "$cur_gid" -exec chgrp -h "$gid" {} + 2>/dev/null || true
        fi
        if [[ "$cur_uid" != "$uid" ]]; then
            log_warning "$name UID 정렬: $cur_uid → $uid"
            pkill -KILL -u "$name" 2>/dev/null || true
            sleep 1
            usermod -u "$uid" "$name" 2>/dev/null || true
            find / -xdev -uid "$cur_uid" -exec chown -h "$uid" {} + 2>/dev/null || true
        fi
        log_info "$name OK (UID=$(id -u $name) GID=$(id -g $name))"
    else
        groupadd -g "$gid" "$name" 2>/dev/null || groupadd "$name" 2>/dev/null || true
        useradd -r -u "$uid" -g "$gid" -s "$shell" -d /nonexistent "$name" 2>/dev/null \
            || useradd -r -g "$name" -s "$shell" -d /nonexistent "$name"
        log_success "$name 신규 생성 (UID=$(id -u $name) GID=$(id -g $name))"
    fi
}

log_info "Ensuring slurm/munge users..."
ensure_service_user slurm "$SLURM_UID" "$SLURM_GID" /bin/false
ensure_service_user munge "$MUNGE_UID" "$MUNGE_GID" /sbin/nologin

# 디렉토리 복사
# tar.gz 압축 해제 후 opt/slurm 디렉토리가 SCRIPT_DIR 안에 생성됨
log_info "Copying Slurm binaries..."
log_info "  Source: ${SCRIPT_DIR}/opt/slurm"
log_info "  Destination: $INSTALL_PREFIX"

if [[ -d "${SCRIPT_DIR}/opt/slurm" ]]; then
    mkdir -p "$INSTALL_PREFIX"
    cp -a "${SCRIPT_DIR}/opt/slurm"/* "$INSTALL_PREFIX/"
    log_success "Slurm binaries copied successfully"
else
    log_error "Source directory not found: ${SCRIPT_DIR}/opt/slurm"
    log_error "tar extraction may have failed. Contents of SCRIPT_DIR:"
    ls -la "$SCRIPT_DIR"
    exit 1
fi

# 심볼릭 링크 생성 (기존 디렉토리/파일 우선 제거)
log_info "Creating symbolic links..."

# /usr/local/slurm이 이미 디렉토리로 존재하면 제거 (심볼릭 링크로 교체)
if [[ -e /usr/local/slurm && ! -L /usr/local/slurm ]]; then
    log_warning "/usr/local/slurm exists as directory/file, removing to create symlink..."
    rm -rf /usr/local/slurm
fi

# 심볼릭 링크 생성 (기존 링크도 덮어씀)
ln -sfn "$INSTALL_PREFIX" /usr/local/slurm
log_info "Created symlink: /usr/local/slurm -> $INSTALL_PREFIX"

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

# 심볼릭 링크 검증 (상세 디버깅)
log_info "Checking /usr/local/slurm status..."
log_info "  Is symlink (-L): $([[ -L /usr/local/slurm ]] && echo yes || echo no)"
log_info "  Exists (-e): $([[ -e /usr/local/slurm ]] && echo yes || echo no)"
log_info "  Is dir (-d): $([[ -d /usr/local/slurm ]] && echo yes || echo no)"
log_info "  readlink: $(readlink /usr/local/slurm 2>/dev/null || echo 'N/A')"
log_info "  ls -la: $(ls -la /usr/local/slurm 2>&1 | head -1)"

# bin 디렉토리 확인
if [[ -d /usr/local/slurm/bin ]]; then
    log_info "  /usr/local/slurm/bin exists: yes"
    log_info "  sinfo exists: $([[ -x /usr/local/slurm/bin/sinfo ]] && echo yes || echo no)"
else
    log_info "  /usr/local/slurm/bin exists: no"
    log_info "  Checking $INSTALL_PREFIX/bin directly..."
    log_info "  $INSTALL_PREFIX/bin exists: $([[ -d $INSTALL_PREFIX/bin ]] && echo yes || echo no)"
fi

# 심볼릭 링크 또는 직접 디렉토리 모두 허용
if [[ -d /usr/local/slurm/bin && -x /usr/local/slurm/bin/sinfo ]]; then
    log_success "Symbolic link verified: /usr/local/slurm -> $(readlink -f /usr/local/slurm)"
else
    log_error "Symbolic link failed! /usr/local/slurm does not point to valid directory"
    log_error "Expected: $INSTALL_PREFIX with bin/sinfo"
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
