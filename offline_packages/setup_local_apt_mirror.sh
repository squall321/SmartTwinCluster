#!/bin/bash
################################################################################
# 로컬 APT 미러 구축 스크립트
#
# 설명:
#   Ubuntu APT 저장소의 로컬 미러를 생성하여 오프라인 환경에서
#   패키지 설치를 가능하게 합니다.
#
# 요구사항:
#   - 인터넷 연결 (헤드 노드에서만)
#   - 최소 50GB 디스크 공간
#   - apt-mirror 패키지
#
# 사용법:
#   sudo ./setup_local_apt_mirror.sh [OPTIONS]
#
# 옵션:
#   --mirror-dir PATH    미러 저장 경로 (기본: /opt/apt-mirror)
#   --repos REPOS        미러링할 저장소 (기본: main,universe,multiverse)
#   --arch ARCH          아키텍처 (기본: amd64)
#   --skip-sync          apt-mirror 동기화 건너뛰기
#   --serve-only         HTTP 서버만 설정
#   --help               도움말 표시
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
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_DIR="/opt/apt-mirror"
MIRROR_REPOS="main,universe,multiverse"
MIRROR_ARCH="amd64"
SKIP_SYNC=false
SERVE_ONLY=false
HTTP_PORT=9999

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 도움말
show_help() {
    head -n 30 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mirror-dir)
                MIRROR_DIR="$2"
                shift 2
                ;;
            --repos)
                MIRROR_REPOS="$2"
                shift 2
                ;;
            --arch)
                MIRROR_ARCH="$2"
                shift 2
                ;;
            --skip-sync)
                SKIP_SYNC=true
                shift
                ;;
            --serve-only)
                SERVE_ONLY=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Root 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# OS 버전 확인
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_CODENAME
        OS_VERSION_ID=$VERSION_ID
        log_info "Detected OS: $OS_ID $OS_VERSION ($OS_VERSION_ID)"
    else
        log_error "Cannot detect OS version"
        exit 1
    fi

    if [[ "$OS_ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only"
        log_error "For CentOS/RHEL, use createrepo/reposync instead"
        exit 1
    fi
}

# apt-mirror 설치
install_apt_mirror() {
    log_info "Installing apt-mirror and dependencies..."

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apt-mirror \
        apache2 \
        wget \
        curl

    log_success "apt-mirror installed"
}

# apt-mirror 설정 생성
configure_apt_mirror() {
    log_info "Configuring apt-mirror..."

    local mirror_config="/etc/apt/mirror.list"
    local base_path="${MIRROR_DIR}/mirror"
    local var_path="${MIRROR_DIR}/var"

    # 디렉토리 생성
    mkdir -p "$base_path" "$var_path"

    # Ubuntu 미러 URL (한국 미러 사용)
    local UBUNTU_MIRROR="http://mirror.kakao.com/ubuntu"

    # mirror.list 생성
    cat > "$mirror_config" << EOF
############# config ##################
#
set base_path    ${base_path}
set mirror_path  \$base_path/mirror
set skel_path    \$base_path/skel
set var_path     ${var_path}
set cleanscript  \$var_path/clean.sh
set defaultarch  ${MIRROR_ARCH}
set postmirror_script \$var_path/postmirror.sh
set run_postmirror 0
set nthreads     20
set _tilde 0
#
############# end config ##############

EOF

    # 저장소 목록 추가
    IFS=',' read -ra REPO_ARRAY <<< "$MIRROR_REPOS"

    log_info "Mirroring Ubuntu $OS_VERSION ($OS_VERSION_ID) repositories..."

    for repo in "${REPO_ARRAY[@]}"; do
        repo=$(echo "$repo" | xargs)  # trim whitespace
        echo "deb ${UBUNTU_MIRROR} ${OS_VERSION} ${repo}" >> "$mirror_config"
        echo "deb ${UBUNTU_MIRROR} ${OS_VERSION}-updates ${repo}" >> "$mirror_config"
        echo "deb ${UBUNTU_MIRROR} ${OS_VERSION}-security ${repo}" >> "$mirror_config"
        log_info "  Added: $repo (+ updates, security)"
    done

    # clean script
    echo "deb-${MIRROR_ARCH} ${UBUNTU_MIRROR} ${OS_VERSION} ${MIRROR_REPOS}" >> "$mirror_config"

    log_success "apt-mirror configuration created: $mirror_config"
    log_info "Configuration preview:"
    cat "$mirror_config" | grep "^deb"
}

# apt-mirror 실행 (동기화)
run_apt_mirror() {
    log_info "Running apt-mirror (this may take 30-60 minutes)..."
    log_warning "Estimated download size: 20-50 GB depending on repositories"
    echo ""

    read -p "Continue with mirroring? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Mirroring cancelled"
        return 0
    fi

    log_info "Starting apt-mirror..."
    apt-mirror 2>&1 | tee "${MIRROR_DIR}/apt-mirror.log"

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "apt-mirror completed successfully"
    else
        log_error "apt-mirror failed"
        return 1
    fi
}

# Apache 웹 서버 설정
setup_apache() {
    log_info "Configuring Apache web server..."

    local apache_config="/etc/apache2/sites-available/apt-mirror.conf"
    local mirror_root="${MIRROR_DIR}/mirror/mirror.kakao.com/ubuntu"

    # Apache 설정 파일 생성
    cat > "$apache_config" << EOF
<VirtualHost *:${HTTP_PORT}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${mirror_root}

    <Directory ${mirror_root}>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/apt-mirror-error.log
    CustomLog \${APACHE_LOG_DIR}/apt-mirror-access.log combined
</VirtualHost>
EOF

    # 포트 설정
    if ! grep -q "Listen ${HTTP_PORT}" /etc/apache2/ports.conf; then
        echo "Listen ${HTTP_PORT}" >> /etc/apache2/ports.conf
    fi

    # 사이트 활성화
    a2ensite apt-mirror.conf
    a2dissite 000-default.conf 2>/dev/null || true

    # Apache 재시작
    systemctl restart apache2
    systemctl enable apache2

    log_success "Apache configured on port ${HTTP_PORT}"
}

# 클라이언트 설정 스크립트 생성
create_client_setup_script() {
    log_info "Creating client setup script..."

    local client_script="${MIRROR_DIR}/setup_client.sh"
    local server_ip=$(hostname -I | awk '{print $1}')

    cat > "$client_script" << 'EOF'
#!/bin/bash
################################################################################
# APT 클라이언트 설정 스크립트 (계산 노드에서 실행)
################################################################################

set -e

MIRROR_SERVER="${1:-MIRROR_SERVER_IP}"
MIRROR_PORT="${2:-9999}"
OS_VERSION=$(lsb_release -cs)

echo "Configuring APT to use local mirror: http://${MIRROR_SERVER}:${MIRROR_PORT}"

# 기존 sources.list 백업
if [[ ! -f /etc/apt/sources.list.backup ]]; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    echo "Backup created: /etc/apt/sources.list.backup"
fi

# 새 sources.list 생성
sudo tee /etc/apt/sources.list > /dev/null << EOFAPT
# Local APT Mirror
deb http://${MIRROR_SERVER}:${MIRROR_PORT} ${OS_VERSION} main universe multiverse
deb http://${MIRROR_SERVER}:${MIRROR_PORT} ${OS_VERSION}-updates main universe multiverse
deb http://${MIRROR_SERVER}:${MIRROR_PORT} ${OS_VERSION}-security main universe multiverse
EOFAPT

echo "APT sources updated"

# APT 업데이트
echo "Running apt-get update..."
sudo apt-get update

echo ""
echo "✅ APT client configuration complete!"
echo "   All packages will now be installed from: http://${MIRROR_SERVER}:${MIRROR_PORT}"
echo ""
echo "To revert to original configuration:"
echo "   sudo mv /etc/apt/sources.list.backup /etc/apt/sources.list"
echo "   sudo apt-get update"
EOF

    # SERVER_IP 치환
    sed -i "s/MIRROR_SERVER_IP/${server_ip}/g" "$client_script"
    chmod +x "$client_script"

    log_success "Client setup script created: $client_script"
    log_info "To configure compute nodes, run on each node:"
    log_info "  scp $client_script user@node:/tmp/"
    log_info "  ssh user@node 'sudo bash /tmp/setup_client.sh'"
}

# 미러 상태 확인
verify_mirror() {
    log_info "Verifying mirror setup..."

    local server_ip=$(hostname -I | awk '{print $1}')
    local test_url="http://${server_ip}:${HTTP_PORT}/dists/"

    if curl -s -f "$test_url" > /dev/null; then
        log_success "Mirror is accessible at: $test_url"
    else
        log_error "Mirror is not accessible"
        return 1
    fi

    # 패키지 카운트
    local package_count=$(find "${MIRROR_DIR}/mirror" -name "*.deb" 2>/dev/null | wc -l)
    log_info "Total packages mirrored: $package_count"

    # 디스크 사용량
    local disk_usage=$(du -sh "${MIRROR_DIR}" 2>/dev/null | cut -f1)
    log_info "Mirror disk usage: $disk_usage"
}

# 요약 정보 출력
print_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          로컬 APT 미러 설정 완료!                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Mirror Information:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mirror Directory: ${MIRROR_DIR}"
    echo "  HTTP Server:      http://${server_ip}:${HTTP_PORT}"
    echo "  Repositories:     ${MIRROR_REPOS}"
    echo "  Architecture:     ${MIRROR_ARCH}"
    echo "  OS Version:       Ubuntu ${OS_VERSION} (${OS_VERSION_ID})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Next Steps:"
    echo "  1. Configure compute nodes:"
    echo "     bash ${MIRROR_DIR}/setup_client.sh"
    echo ""
    echo "  2. Or manually edit /etc/apt/sources.list on each node:"
    echo "     deb http://${server_ip}:${HTTP_PORT} ${OS_VERSION} main universe multiverse"
    echo ""
    echo "  3. Update mirror periodically:"
    echo "     sudo apt-mirror"
    echo ""
    log_info "To serve this mirror on boot:"
    echo "  sudo systemctl enable apache2"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        로컬 APT 미러 구축 스크립트                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    detect_os

    if [[ "$SERVE_ONLY" == "false" ]]; then
        install_apt_mirror
        configure_apt_mirror

        if [[ "$SKIP_SYNC" == "false" ]]; then
            run_apt_mirror
        else
            log_warning "Skipping mirror synchronization (--skip-sync)"
        fi
    fi

    setup_apache
    create_client_setup_script
    verify_mirror
    print_summary

    log_success "APT mirror setup complete!"
}

main "$@"
