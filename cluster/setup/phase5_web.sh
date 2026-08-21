#!/bin/bash

################################################################################
# Phase 5: Web Services Setup Script
#
# This script sets up web services on controllers with web: true
# - Deploys 8 web services (dashboard, auth, job API, websocket, etc.)
# - Configures Nginx reverse proxy with SSL
# - Sets up Let's Encrypt SSL certificates
# - Configures systemd services for all web services
# - Integrates with Redis and MariaDB
# - Sets up health checks and monitoring
#
# Usage:
#   sudo ./phase5_web.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../../my_multihead_cluster.yaml)
#   --dry-run           Preview actions without executing
#   --skip-ssl          Skip SSL certificate generation (for testing)
#   --force             Force setup even if already configured
#   --help              Show this help message
#
# Example:
#   sudo ./phase5_web.sh --config ../my_multihead_cluster.yaml
#   sudo ./phase5_web.sh --dry-run
#   sudo ./phase5_web.sh --skip-ssl --force
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/ssh_helpers.sh" 2>/dev/null || true
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
DRY_RUN=false
SKIP_SSL=false
FORCE=false
LOG_FILE="/var/log/cluster_web_setup.log"

# SSH options for secure remote connections
# GSSAPIAuthentication=no: Disable Kerberos to prevent delays
# PreferredAuthentications=publickey: Only try publickey auth
#
# IMPORTANT: When running with sudo, we need to use the original user's SSH key
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"

_SSH_BASE_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3"

if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes $_SSH_BASE_OPTS -o PreferredAuthentications=publickey"
else
    SSH_OPTS="-o BatchMode=yes $_SSH_BASE_OPTS -o PreferredAuthentications=publickey"
fi

# per-node SSH 인증: 대상 user 키 우선, sshpass fallback
setup_node_ssh_opts() {
    local user="$1" ip="$2"
    local user_home
    user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || echo "")
    for _k in "${user_home}/.ssh/id_ed25519" "${user_home}/.ssh/id_rsa" "$SSH_KEY_FILE"; do
        [[ -f "$_k" ]] || continue
        if ssh -n -i "$_k" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
               "$user@$ip" "exit" &>/dev/null; then
            SSH_OPTS="-i $_k -o BatchMode=yes $_SSH_BASE_OPTS"
            return 0
        fi
    done
    local _pass
    _pass=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('cluster_info',{}).get('ssh_password',''))" 2>/dev/null || echo "")
    if [[ -n "$_pass" ]] && command -v sshpass &>/dev/null; then
        if SSHPASS="$_pass" sshpass -e ssh -n -o BatchMode=no -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no "$user@$ip" "exit" &>/dev/null; then
            export SSHPASS="$_pass"
            SSH_OPTS="-o BatchMode=no $_SSH_BASE_OPTS"
            return 0
        fi
    fi
    return 1
}

# Web services configuration
WEB_SERVICES_DIR="/opt/web_services"
WEB_CONFIG_TEMPLATE="$SCRIPT_DIR/../config/web_services_template.yaml"
NGINX_TEMPLATE="$SCRIPT_DIR/../config/nginx_web_template.conf"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show help
show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Convert CONFIG_PATH to absolute path (important for cd operations later)
    if [[ -n "$CONFIG_PATH" && "${CONFIG_PATH:0:1}" != "/" ]]; then
        CONFIG_PATH="$(cd "$(dirname "$CONFIG_PATH")" 2>/dev/null && pwd)/$(basename "$CONFIG_PATH")"
    fi
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_deps=()

    # Read SSL mode from YAML config to determine if certbot is needed
    local ssl_mode
    ssl_mode=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('mode', 'self_signed'))" 2>/dev/null || echo "self_signed")

    # Base required commands (certbot only needed for letsencrypt mode)
    local required_cmds=(python3 node npm nginx jq)
    if [[ "$ssl_mode" == "letsencrypt" ]]; then
        required_cmds+=(certbot)
        log_info "SSL mode: letsencrypt - certbot required"
    else
        log_info "SSL mode: $ssl_mode - certbot not required"
    fi

    # Check for required commands
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."

        if [[ "$DRY_RUN" == false ]]; then
            apt-get update
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    node|npm)
                        # Install Node.js from offline packages (nodesource.com not available offline)
                        local apt_pkg_dir="${OFFLINE_PKG_DIR}/apt_packages"
                        if [[ -d "$apt_pkg_dir" ]]; then
                            log_info "Installing nodejs from offline packages..."
                            # Fix Packages file permissions (apt needs read access)
                            chmod 644 "$apt_pkg_dir/Packages" 2>/dev/null || true
                            # Use dpkg directly to install nodejs .deb from offline dir
                            local node_deb
                            node_deb=$(ls "$apt_pkg_dir"/nodejs_*.deb 2>/dev/null | head -1)
                            if [[ -n "$node_deb" ]]; then
                                dpkg -i "$node_deb" || apt-get install -f -y
                            else
                                apt-get install -y nodejs npm || log_warning "nodejs not found in offline packages"
                            fi
                        else
                            log_warning "Offline package dir not found: $apt_pkg_dir"
                            apt-get install -y nodejs npm || true
                        fi
                        ;;
                    certbot)
                        # Only install certbot if letsencrypt mode is selected
                        log_info "Installing certbot for Let's Encrypt SSL..."
                        apt-get install -y certbot python3-certbot-nginx
                        ;;
                    *)
                        apt-get install -y "$dep"
                        ;;
                esac
            done
        else
            log_info "[DRY-RUN] Would install: ${missing_deps[*]}"
        fi
    fi

    # Check if config file exists
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi

    # Check if parser.py exists
    if [[ ! -f "$SCRIPT_DIR/../config/parser.py" ]]; then
        log_error "Parser script not found: $SCRIPT_DIR/../config/parser.py"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to stop existing services before setup
stop_existing_services() {
    log_info "Stopping existing services before setup..."

    if [[ "$DRY_RUN" == false ]]; then
        # Stop nginx if running
        if systemctl is-active --quiet nginx 2>/dev/null; then
            log_info "Stopping nginx..."
            systemctl stop nginx 2>/dev/null || true
            sleep 1
            log_success "nginx stopped"
        fi

        # Stop redis if running
        if systemctl is-active --quiet redis-server 2>/dev/null; then
            log_info "Stopping redis-server..."
            systemctl stop redis-server 2>/dev/null || true
            sleep 1
            log_success "redis-server stopped"
        elif systemctl is-active --quiet redis 2>/dev/null; then
            log_info "Stopping redis..."
            systemctl stop redis 2>/dev/null || true
            sleep 1
            log_success "redis stopped"
        elif pgrep -x redis-server > /dev/null 2>&1; then
            log_info "Stopping redis-server (manual)..."
            pkill -TERM redis-server 2>/dev/null || true
            sleep 1
            pkill -KILL redis-server 2>/dev/null || true
            log_success "redis-server stopped"
        fi

        # Stop gunicorn processes
        if pgrep -f "gunicorn" > /dev/null 2>&1; then
            log_info "Stopping gunicorn processes..."
            pkill -TERM -f "gunicorn" 2>/dev/null || true
            sleep 2
            pkill -KILL -f "gunicorn" 2>/dev/null || true
            log_success "gunicorn processes stopped"
        fi

        # Stop any running backend services
        local services=("auth_portal_4430" "backend_5010" "websocket_5011" "kooCAEWebServer_5000" "kooCAEWebAutomationServer_5001")
        for svc in "${services[@]}"; do
            if pgrep -f "$svc" > /dev/null 2>&1; then
                log_info "Stopping $svc..."
                pkill -TERM -f "$svc" 2>/dev/null || true
                sleep 1
            fi
        done

        # ============================================================================
        # 기존 HPC 관련 systemd 서비스 정리 (clean install 보장)
        # ============================================================================
        log_info "Cleaning up existing HPC systemd services..."
        local hpc_services=(
            "auth_backend" "auth_frontend" "dashboard_backend" "websocket_service"
            "cae_backend" "cae_automation" "saml_idp" "vnc_service"
            "prometheus" "node_exporter" "moonlight_backend"
        )
        for svc in "${hpc_services[@]}"; do
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                log_info "  Stopping $svc..."
                systemctl stop "$svc" 2>/dev/null || true
            fi
            if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                log_info "  Disabling $svc..."
                systemctl disable "$svc" 2>/dev/null || true
            fi
            if [[ -f "/etc/systemd/system/${svc}.service" ]]; then
                log_info "  Removing ${svc}.service..."
                rm -f "/etc/systemd/system/${svc}.service"
            fi
        done

        # ============================================================================
        # Nginx 중복 설정 정리
        # ============================================================================
        log_info "Cleaning up duplicate Nginx configurations..."

        # sites-enabled에서 HPC 관련 심볼릭 링크 제거 (conf.d 사용)
        rm -f /etc/nginx/sites-enabled/hpc-portal.conf 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/hpc_web_services.conf 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/auth-portal.conf 2>/dev/null || true

        # conf.d에서 백업/disabled 파일 정리
        rm -f /etc/nginx/conf.d/*.backup* 2>/dev/null || true
        rm -f /etc/nginx/conf.d/*.disabled* 2>/dev/null || true
        rm -f /etc/nginx/conf.d/*.bak 2>/dev/null || true

        log_success "Nginx configurations cleaned up"

        # systemd 데몬 리로드
        systemctl daemon-reload
        log_success "Existing HPC services cleaned up"
    else
        log_info "[DRY-RUN] Would stop nginx, redis, and backend services"
        log_info "[DRY-RUN] Would clean up existing HPC systemd services"
        log_info "[DRY-RUN] Would clean up duplicate Nginx configurations"
    fi
}

# Pre-validate port conflicts (report only, no kill)
preflight_port_check() {
    local ports_to_check=(4430 4431 5000 5001 5010 5011 5173 5174 3000 3001 7000 8888 8889 8501 8502 9090 9100)
    local conflicts=0

    for port in "${ports_to_check[@]}"; do
        local pid_info=$(ss -tlnp "sport = :$port" 2>/dev/null | grep -v "^State" | head -1)
        if [[ -n "$pid_info" ]]; then
            log_warning "Port $port already in use: $pid_info"
            conflicts=$((conflicts + 1))
        fi
    done

    if [[ $conflicts -gt 0 ]]; then
        log_warning "$conflicts port conflict(s) detected. These will be stopped during setup."
    else
        log_success "No port conflicts detected"
    fi
}

# Function to stop conflicting manual web services
stop_manual_web_services() {
    log_info "Checking for manually running web services on common ports..."

    local ports_to_check=(4430 4431 5000 5001 5010 5011 5173 5174 3000 3001 7000 8888 8889 8501 8502 9090 9100)
    local processes_killed=0

    for port in "${ports_to_check[@]}"; do
        # Find PIDs using this port
        local pids=$(lsof -ti:$port 2>/dev/null || true)

        if [[ -n "$pids" ]]; then
            log_warning "Port $port is in use by PIDs: $pids"

            # Get process details
            for pid in $pids; do
                local process_info=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
                log_info "  - PID $pid: $process_info"

                if [[ "$DRY_RUN" == false ]]; then
                    # Try graceful kill first
                    if kill -TERM $pid 2>/dev/null || true; then
                        log_info "  - Sent SIGTERM to PID $pid"
                        processes_killed=$((processes_killed + 1))
                        sleep 1

                        # Check if still running
                        if kill -0 $pid 2>/dev/null; then
                            # Force kill if still running
                            if kill -KILL $pid 2>/dev/null; then
                                log_warning "  - Force killed PID $pid"
                            fi
                        else
                            log_success "  - Process $pid terminated gracefully"
                        fi
                    else
                        log_warning "  - Failed to kill PID $pid (may have already exited)"
                    fi
                else
                    log_info "[DRY-RUN] Would kill PID $pid ($process_info) on port $port"
                fi
            done
        fi
    done

    if [[ $processes_killed -gt 0 ]]; then
        log_success "Stopped $processes_killed manually running web service processes"
        # Wait for ports to be released
        sleep 2
    else
        log_info "No conflicting manual web services found"
    fi

    # Also stop any Vite dev servers
    local vite_pids=$(pgrep -f "vite" 2>/dev/null || true)
    if [[ -n "$vite_pids" ]]; then
        log_warning "Found Vite dev servers running: $vite_pids"
        if [[ "$DRY_RUN" == false ]]; then
            pkill -TERM -f "vite" 2>/dev/null || true
            sleep 1
            pkill -KILL -f "vite" 2>/dev/null || true
            log_success "Stopped Vite dev servers"
        else
            log_info "[DRY-RUN] Would stop Vite dev servers"
        fi
    fi
}

# Function to load configuration
load_config() {
    log_info "Loading configuration from $CONFIG_PATH..."

    # Use parser.py to load configuration
    local config_json
    config_json=$(python3 "$SCRIPT_DIR/../config/parser.py" "$CONFIG_PATH" get-controllers --service web)

    if [[ -z "$config_json" || "$config_json" == "[]" ]]; then
        log_error "No controllers with web service enabled found in configuration"
        exit 1
    fi

    # Get all IPs on this machine
    ALL_IPS=$(hostname -I)

    # Check if any of this machine's IPs match a web controller
    WEB_ENABLED="false"
    CURRENT_NODE_IP=""

    for ip in $ALL_IPS; do
        MATCH=$(echo "$config_json" | jq -r --arg ip "$ip" '.[] | select(.ip_address == $ip) | .services.web')
        if [[ "$MATCH" == "true" ]]; then
            WEB_ENABLED="true"
            CURRENT_NODE_IP="$ip"
            break
        fi
    done

    if [[ "$WEB_ENABLED" != "true" ]]; then
        log_error "This node (IPs: $ALL_IPS) is not configured for web services"
        log_info "Available web controllers:"
        echo "$config_json" | jq -r '.[] | "\(.hostname) (\(.ip_address))"'
        exit 1
    fi

    # Load cluster-wide settings using direct YAML parsing
    CLUSTER_NAME=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('cluster_info', {}).get('cluster_name', 'hpc-cluster'))")
    DOMAIN=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('cluster_info', {}).get('domain', 'hpc.local'))")
    DB_VIP=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('vip', ''))" || echo "")
    DB_USER=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('mariadb', {}).get('user', 'hpcadmin'))")

    # Helper function to resolve ${VAR} references from environment section
    resolve_env_var() {
        local value="$1"
        local env_section
        if [[ "$value" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            env_section=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('$var_name', ''))" 2>/dev/null)
            echo "$env_section"
        else
            echo "$value"
        fi
    }

    # Get passwords - resolve ${VAR} references from environment section
    local raw_db_password=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('mariadb', {}).get('root_password', ''))")
    DB_PASSWORD=$(resolve_env_var "$raw_db_password")
    # Fallback: try environment.DB_ROOT_PASSWORD directly
    if [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" == '${DB_ROOT_PASSWORD}' ]]; then
        DB_PASSWORD=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('DB_ROOT_PASSWORD', ''))" 2>/dev/null)
    fi

    local raw_redis_password=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('redis', {}).get('cluster', {}).get('password', '') or c.get('redis', {}).get('password', ''))")
    REDIS_PASSWORD=$(resolve_env_var "$raw_redis_password")
    # Fallback: try environment.REDIS_PASSWORD directly
    if [[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == '${REDIS_PASSWORD}' ]]; then
        REDIS_PASSWORD=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('REDIS_PASSWORD', ''))" 2>/dev/null)
    fi

    # Redis Sentinel(HA) — environment.REDIS_SENTINEL_HOSTS 있으면 클라이언트가 Sentinel 로 연결.
    # 없으면 빈값 → 클라이언트는 단일 Redis(REDIS_HOST)로 동작(하위호환).
    REDIS_SENTINEL_HOSTS=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('REDIS_SENTINEL_HOSTS', ''))" 2>/dev/null)
    REDIS_MASTER_NAME=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('REDIS_MASTER_NAME', '') or 'mymaster')" 2>/dev/null)

    local raw_session_secret=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web_services', {}).get('session_secret', ''))")
    SESSION_SECRET=$(resolve_env_var "$raw_session_secret")

    local raw_jwt_secret=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web_services', {}).get('jwt_secret', ''))")
    JWT_SECRET=$(resolve_env_var "$raw_jwt_secret")
    # Fallback: try environment.JWT_SECRET_KEY directly
    if [[ -z "$JWT_SECRET" || "$JWT_SECRET" == '${JWT_SECRET_KEY}' ]]; then
        JWT_SECRET=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('JWT_SECRET_KEY', ''))" 2>/dev/null)
    fi

    # Validate security-sensitive configurations
    local config_warnings=false
    if [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" == "changeme" ]]; then
        log_warning "⚠️  database.mariadb.root_password not set - using insecure default"
        DB_PASSWORD="changeme"
        config_warnings=true
    fi
    if [[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == "changeme" ]]; then
        log_warning "⚠️  redis.password not set - using insecure default"
        REDIS_PASSWORD="changeme"
        config_warnings=true
    fi
    if [[ -z "$SESSION_SECRET" || "$SESSION_SECRET" == "change-this-secret" ]]; then
        log_warning "⚠️  web_services.session_secret not set - using insecure default"
        SESSION_SECRET="change-this-secret"
        config_warnings=true
    fi
    if [[ -z "$JWT_SECRET" || "$JWT_SECRET" == "change-this-jwt-secret" ]]; then
        log_warning "⚠️  web_services.jwt_secret not set - using insecure default"
        JWT_SECRET="change-this-jwt-secret"
        config_warnings=true
    fi

    if [[ "$config_warnings" == "true" && "$DRY_RUN" == "false" ]]; then
        log_warning ""
        log_warning "=== SECURITY NOTICE ==="
        log_warning "Some security settings are using insecure defaults."
        log_warning "Please configure proper secrets in $CONFIG_PATH"
        log_warning ""
    fi

    # Get all web controllers for upstream configuration
    WEB_CONTROLLERS=$(echo "$config_json" | jq -r '.[] | "\(.ip_address):\(.hostname)"')

    # Load public URL for dashboard access
    PUBLIC_URL=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('public_url', '127.0.0.1'))" 2>/dev/null || echo "127.0.0.1")
    if [[ -z "$PUBLIC_URL" || "$PUBLIC_URL" == "null" ]]; then
        log_warning "web.public_url not set in YAML, using current node IP: $CURRENT_NODE_IP"
        PUBLIC_URL="$CURRENT_NODE_IP"
    fi

    # Load SSO configuration
    SSO_ENABLED=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(str(c.get('sso', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")
    log_info "SSO Enabled: $SSO_ENABLED"

    log_success "Configuration loaded successfully"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Domain: $DOMAIN"
    log_info "Current node: $CURRENT_NODE_IP"
    log_info "Public URL: $PUBLIC_URL"
}

# Function to create web services user
create_web_user() {
    log_info "Creating web services user..."

    # YAML에서 service_user 읽기 (기본값: webservice)
    local service_user="webservice"
    if [[ -f "$CONFIG_PATH" ]]; then
        local yaml_service_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
        if [[ -n "$yaml_service_user" ]]; then
            service_user="$yaml_service_user"
        fi
    fi

    # 이미 존재하는 사용자라면 (koopark 등) 새로 생성하지 않음
    if id "$service_user" &>/dev/null; then
        local existing_uid=$(id -u "$service_user")
        log_info "Service user '$service_user' already exists (UID=$existing_uid)"
        return 0
    fi

    # Get UID/GID from YAML config (default to 64010 to avoid conflicts)
    local target_uid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web',{}).get('user_uid', 64010))" 2>/dev/null || echo 64010)
    local target_gid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web',{}).get('user_gid', 64010))" 2>/dev/null || echo 64010)

    if [[ "$DRY_RUN" == false ]]; then
        # Create group first
        if ! getent group "$service_user" &>/dev/null; then
            groupadd -g "$target_gid" "$service_user" 2>/dev/null || groupadd "$service_user"
        fi
        # Create user with specific UID if possible
        useradd -r -u "$target_uid" -g "$service_user" -s /bin/false -d "$WEB_SERVICES_DIR" "$service_user" 2>/dev/null || \
            useradd -r -g "$service_user" -s /bin/false -d "$WEB_SERVICES_DIR" "$service_user"
        log_success "User '$service_user' created (UID=$(id -u "$service_user"))"
    else
        log_info "[DRY-RUN] Would create user '$service_user' with UID=$target_uid"
    fi
}

# Function to create directory structure
create_directories() {
    log_info "Creating directory structure..."

    # YAML에서 service_user/service_group 읽기 (기본값: 현재 사용자)
    local service_user="${SERVICE_USER:-$(whoami)}"
    local service_group="${SERVICE_GROUP:-$(id -gn)}"
    if [[ -f "$CONFIG_PATH" ]]; then
        local yaml_service_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
        local yaml_service_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
        if [[ -n "$yaml_service_user" ]]; then
            service_user="$yaml_service_user"
        fi
        if [[ -n "$yaml_service_group" ]]; then
            service_group="$yaml_service_group"
        fi
    fi

    local dirs=(
        "$WEB_SERVICES_DIR"
        "$WEB_SERVICES_DIR/dashboard"
        "$WEB_SERVICES_DIR/auth_service"
        "$WEB_SERVICES_DIR/job_api"
        "$WEB_SERVICES_DIR/websocket_service"
        "$WEB_SERVICES_DIR/file_service"
        "$WEB_SERVICES_DIR/monitoring_dashboard"
        "$WEB_SERVICES_DIR/metrics_api"
        "$WEB_SERVICES_DIR/admin_portal"
        "$WEB_SERVICES_DIR/config"
        "$WEB_SERVICES_DIR/uploads"
        "/var/log/web_services"
    )

    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$dir"
            chown -R "$service_user:$service_group" "$dir" 2>/dev/null || true
        else
            log_info "[DRY-RUN] Would create directory: $dir"
        fi
    done

    log_success "Directory structure created"
}

# Function to deploy real dashboard services from source
deploy_real_dashboard_service() {
    local service_name=$1
    local source_dir=$2
    local port=$3
    local service_type=$4  # python or node
    local start_command=$5

    log_info "Deploying $service_name from $source_dir..."

    local target_dir="$WEB_SERVICES_DIR/$service_name"
    local dashboard_base="$PROJECT_ROOT/dashboard"

    if [[ "$DRY_RUN" == false ]]; then
        # Create target directory
        mkdir -p "$target_dir"

        # Copy service files from dashboard
        if [[ -d "$dashboard_base/$source_dir" ]]; then
            log_info "Copying files from $dashboard_base/$source_dir to $target_dir"
            rsync -av --exclude='venv' --exclude='node_modules' --exclude='logs' --exclude='*.pid' \
                --exclude='__pycache__' --exclude='*.pyc' --exclude='dist' --exclude='.vite' \
                "$dashboard_base/$source_dir/" "$target_dir/"

            # Create logs directory
            mkdir -p "$target_dir/logs"

            # Set ownership (use service_user from YAML or current user)
            local owner_user="${SERVICE_USER:-$(whoami)}"
            local owner_group="${SERVICE_GROUP:-$(id -gn)}"
            if [[ -f "$CONFIG_PATH" ]]; then
                local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                [[ -n "$yaml_user" ]] && owner_user="$yaml_user"
                [[ -n "$yaml_group" ]] && owner_group="$yaml_group"
            fi
            chown -R "$owner_user:$owner_group" "$target_dir"

            log_success "$service_name files copied successfully"
        else
            log_error "Source directory not found: $dashboard_base/$source_dir"
            return 1
        fi
    else
        log_info "[DRY-RUN] Would deploy $service_name from $dashboard_base/$source_dir"
    fi
}

# Function to deploy web service skeleton
deploy_service_skeleton() {
    local service_name=$1
    local service_type=$2  # frontend or backend
    local port=$3

    log_info "Deploying $service_name skeleton..."

    local service_dir="$WEB_SERVICES_DIR/$service_name"

    if [[ "$DRY_RUN" == false ]]; then
        cd "$service_dir"

        # Initialize npm project if not exists
        if [[ ! -f "package.json" ]]; then
            npm init -y
        fi

        if [[ "$service_type" == "frontend" ]]; then
            # Frontend service (React + Vite)
            npm install --save-dev vite @vitejs/plugin-react react react-dom

            # Create basic Vite config
            cat > vite.config.js << EOF
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: ${port}
  },
  preview: {
    host: '0.0.0.0',
    port: ${port}
  }
})
EOF

            # Create basic React app structure
            mkdir -p src public
            cat > src/App.jsx << EOF
import { useState } from 'react'

function App() {
  return (
    <div>
      <h1>${service_name}</h1>
      <p>Service is running on port ${port}</p>
    </div>
  )
}

export default App
EOF

            cat > src/main.jsx << EOF
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
EOF

            cat > index.html << EOF
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${service_name}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

        else
            # Backend service (Express)
            npm install express cors dotenv

            # Create basic Express server
            mkdir -p src
            cat > src/server.js << EOF
const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || ${port};

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: '${service_name}', port: PORT });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(\`${service_name} listening on port \${PORT}\`);
});
EOF

            # Create .env file
            cat > .env << EOF
PORT=${port}
NODE_ENV=production
DB_HOST=${DB_VIP}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_SENTINEL_HOSTS=${REDIS_SENTINEL_HOSTS}
REDIS_MASTER_NAME=${REDIS_MASTER_NAME}
JWT_SECRET=${JWT_SECRET}
SESSION_SECRET=${SESSION_SECRET}
EOF
            chmod 600 .env
        fi

        # Update package.json scripts
        npm pkg set scripts.start="node src/server.js"
        npm pkg set scripts.dev="node src/server.js"

        if [[ "$service_type" == "frontend" ]]; then
            npm pkg set scripts.build="vite build"
            npm pkg set scripts.preview="vite preview --host 0.0.0.0 --port ${port}"

            # Build the frontend for production
            log_info "Building $service_name for production..."
            npm run build || {
                log_error "Failed to build $service_name"
                return 1
            }
            log_success "$service_name built successfully"
        fi

        # Set ownership (use service_user from YAML or current user)
        local owner_user="${SERVICE_USER:-$(whoami)}"
        local owner_group="${SERVICE_GROUP:-$(id -gn)}"
        if [[ -f "$CONFIG_PATH" ]]; then
            local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            [[ -n "$yaml_user" ]] && owner_user="$yaml_user"
            [[ -n "$yaml_group" ]] && owner_group="$yaml_group"
        fi
        chown -R "$owner_user:$owner_group" "$service_dir"

        log_success "$service_name skeleton deployed"
    else
        log_info "[DRY-RUN] Would deploy $service_name skeleton"
    fi
}

# Function to setup Redis session management
# This function configures Redis-based session storage for all dashboard services
# Prerequisites:
#   - dashboard/common/ library must exist (contains RedisSessionManager)
#   - Redis server must be running on localhost:6379
# Services configured:
#   - kooCAEWebServer_5000 (App sessions with TTL=7200s)
#   - backend_5010 (VNC sessions with TTL=28800s)
# Both use legacy key pattern for backward compatibility:
#   - VNC: vnc:session:{id}
#   - App: app:session:{id}
setup_redis_session_management() {
    local dashboard_dir=$1

    log_info "Setting up Redis session management..."

    # Check if common directory exists
    if [[ ! -d "$dashboard_dir/common" ]]; then
        log_error "Common session management library not found at $dashboard_dir/common"
        log_error "Please ensure the common library is present before running setup"
        log_error "Required files: config.py, session_manager.py, __init__.py"
        return 1
    fi

    log_success "Found common session management library"

    # Install redis Python package in required services
    local services_with_redis=(
        "kooCAEWebServer_5000"
        "backend_5010"
    )

    for service in "${services_with_redis[@]}"; do
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            log_warning "Service directory not found: $service_dir, skipping..."
            continue
        fi

        log_info "Installing redis package in $service..."

        if [[ "$DRY_RUN" == false ]]; then
            # Check if venv exists
            if [[ ! -d "$service_dir/venv" ]]; then
                log_warning "No venv found for $service, skipping redis installation"
                continue
            fi

            # Install redis package
            cd "$service_dir"
            source venv/bin/activate
            pip install redis python-dotenv --quiet || {
                log_warning "Failed to install redis package in $service"
            }
            deactivate

            # YAML에서 Slurm bin_path 읽기 (기본값: /usr/local/slurm/bin for Slurm 23.11.10 source build)
            local slurm_bin_path="/usr/local/slurm/bin"
            if [[ -f "$CONFIG_PATH" ]]; then
                local yaml_bin_path=$(grep -E "^\s+bin_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                if [[ -n "$yaml_bin_path" ]]; then
                    slurm_bin_path="$yaml_bin_path"
                else
                    local yaml_install_path=$(grep -E "^\s+install_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    if [[ -n "$yaml_install_path" ]]; then
                        slurm_bin_path="${yaml_install_path}/bin"
                    fi
                fi
            fi

            # Create or update .env file with Redis and Slurm configuration
            if [[ ! -f "$service_dir/.env" ]]; then
                log_info "Creating .env file for $service..."

                # Determine SSH key path based on service user
                local ssh_user="${SERVICE_USER:-$(whoami)}"
                if [[ -f "$CONFIG_PATH" ]]; then
                    local yaml_ssh_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    [[ -n "$yaml_ssh_user" ]] && ssh_user="$yaml_ssh_user"
                fi
                local ssh_key_path="/home/${ssh_user}/.ssh/id_rsa"

                # Determine dashboard SQLite DB path (YAML override, else service_user 홈 기준)
                local db_path="/home/${ssh_user}/web_services/backend/dashboard.db"
                if [[ -f "$CONFIG_PATH" ]]; then
                    local yaml_db_path=$(grep -E "^\s+dashboard_db_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    [[ -n "$yaml_db_path" ]] && db_path="$yaml_db_path"
                fi

                cat > "$service_dir/.env" << EOF
# Redis Configuration for Session Management
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}
REDIS_SENTINEL_HOSTS=${REDIS_SENTINEL_HOSTS}
REDIS_MASTER_NAME=${REDIS_MASTER_NAME:-mymaster}
DEFAULT_SESSION_TTL=7200

# Slurm Configuration
SLURM_BIN_DIR=${slurm_bin_path}

# SSH Configuration (for SSH session management)
SSH_KEY_PATH=${ssh_key_path}

# Database Configuration
DATABASE_PATH=${db_path}
EOF
                # Set ownership (use service_user from YAML or current user)
                local env_owner="${SERVICE_USER:-$(whoami)}"
                local env_group="${SERVICE_GROUP:-$(id -gn)}"
                if [[ -f "$CONFIG_PATH" ]]; then
                    local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    [[ -n "$yaml_user" ]] && env_owner="$yaml_user"
                    [[ -n "$yaml_group" ]] && env_group="$yaml_group"
                fi
                chown "$env_owner:$env_group" "$service_dir/.env"
                log_success ".env file created for $service"
            else
                log_info ".env file already exists for $service"

                # Check and add missing Redis configuration
                local needs_update=false

                if ! grep -q "^REDIS_HOST=" "$service_dir/.env"; then
                    echo "REDIS_HOST=localhost" >> "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^REDIS_PORT=" "$service_dir/.env"; then
                    echo "REDIS_PORT=6379" >> "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^REDIS_PASSWORD=" "$service_dir/.env"; then
                    echo "REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}" >> "$service_dir/.env"
                    needs_update=true
                elif [[ -n "$REDIS_PASSWORD" && "$REDIS_PASSWORD" != "changeme" ]]; then
                    # Update existing REDIS_PASSWORD if YAML provides a real value
                    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=${REDIS_PASSWORD}/" "$service_dir/.env"
                    needs_update=true
                fi

                # Redis Sentinel(HA) 키 — yaml environment 값으로 추가/갱신(없으면 빈값=단일모드)
                if ! grep -q "^REDIS_SENTINEL_HOSTS=" "$service_dir/.env"; then
                    echo "REDIS_SENTINEL_HOSTS=${REDIS_SENTINEL_HOSTS}" >> "$service_dir/.env"
                    needs_update=true
                else
                    sed -i "s|^REDIS_SENTINEL_HOSTS=.*|REDIS_SENTINEL_HOSTS=${REDIS_SENTINEL_HOSTS}|" "$service_dir/.env"
                fi
                if ! grep -q "^REDIS_MASTER_NAME=" "$service_dir/.env"; then
                    echo "REDIS_MASTER_NAME=${REDIS_MASTER_NAME:-mymaster}" >> "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^DEFAULT_SESSION_TTL=" "$service_dir/.env"; then
                    echo "DEFAULT_SESSION_TTL=7200" >> "$service_dir/.env"
                    needs_update=true
                fi

                # Add SLURM_BIN_DIR if missing
                if ! grep -q "^SLURM_BIN_DIR=" "$service_dir/.env"; then
                    echo "" >> "$service_dir/.env"
                    echo "# Slurm Configuration" >> "$service_dir/.env"
                    echo "SLURM_BIN_DIR=${slurm_bin_path}" >> "$service_dir/.env"
                    needs_update=true
                fi

                # Add SSH_KEY_PATH if missing (for backend_5010 SSH session management)
                if ! grep -q "^SSH_KEY_PATH=" "$service_dir/.env"; then
                    local ssh_user="${SERVICE_USER:-$(whoami)}"
                    if [[ -f "$CONFIG_PATH" ]]; then
                        local yaml_ssh_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                        [[ -n "$yaml_ssh_user" ]] && ssh_user="$yaml_ssh_user"
                    fi
                    local ssh_key_path="/home/${ssh_user}/.ssh/id_rsa"
                    echo "" >> "$service_dir/.env"
                    echo "# SSH Configuration (for SSH session management)" >> "$service_dir/.env"
                    echo "SSH_KEY_PATH=${ssh_key_path}" >> "$service_dir/.env"
                    needs_update=true
                fi

                # Add DATABASE_PATH if missing (YAML dashboard_db_path 우선, 없으면 service_user 홈 기준)
                if ! grep -q "^DATABASE_PATH=" "$service_dir/.env"; then
                    local db_user="${SERVICE_USER:-$(whoami)}"
                    local db_path="/home/${db_user}/web_services/backend/dashboard.db"
                    if [[ -f "$CONFIG_PATH" ]]; then
                        local yaml_db_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                        [[ -n "$yaml_db_user" ]] && db_path="/home/${yaml_db_user}/web_services/backend/dashboard.db"
                        local yaml_db_path=$(grep -E "^\s+dashboard_db_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                        [[ -n "$yaml_db_path" ]] && db_path="$yaml_db_path"
                    fi
                    echo "" >> "$service_dir/.env"
                    echo "# Database Configuration" >> "$service_dir/.env"
                    echo "DATABASE_PATH=${db_path}" >> "$service_dir/.env"
                    needs_update=true
                fi

                if [[ "$needs_update" == true ]]; then
                    log_success "Updated .env with missing configuration"
                else
                    log_info "Redis configuration already complete"
                fi
            fi

            log_success "Redis setup completed for $service"
        else
            log_info "[DRY-RUN] Would install redis package in $service"
            log_info "[DRY-RUN] Would create .env file for $service"
        fi
    done

    log_success "Redis session management setup complete"
}

# Function to generate frontend .env files from YAML configuration
# This ensures all frontends use the correct public URL for API/WebSocket/Auth connections
generate_frontend_env_files() {
    local dashboard_dir=$1

    log_info "Generating frontend .env files from YAML configuration..."

    # Determine protocol based on SSO setting
    local PROTOCOL="http"
    local WS_PROTOCOL="ws"
    if [[ "$SSO_ENABLED" == "true" ]]; then
        PROTOCOL="https"
        WS_PROTOCOL="wss"
        log_info "SSO enabled: Using HTTPS/WSS protocols"
    else
        log_info "SSO disabled: Using HTTP/WS protocols"
    fi

    # Frontend services that need .env files
    local frontends=(
        "frontend_3010"      # Main dashboard
        "auth_portal_4431"   # Auth portal
        "vnc_service_8002"   # VNC service
        "kooCAEWeb_5173"     # CAE web interface
    )

    for frontend in "${frontends[@]}"; do
        local frontend_dir="$dashboard_dir/$frontend"
        local env_file="$frontend_dir/.env"

        if [[ ! -d "$frontend_dir" ]]; then
            log_warning "Frontend directory not found: $frontend_dir, skipping..."
            continue
        fi

        if [[ "$DRY_RUN" == false ]]; then
            log_info "Generating .env for $frontend..."

            # Backup existing .env if it exists
            if [[ -f "$env_file" ]]; then
                cp "$env_file" "${env_file}.backup_$(date +%Y%m%d_%H%M%S)"
            fi

            # Generate .env based on frontend type
            # All frontends use Nginx proxy paths (no port numbers)
            case "$frontend" in
                frontend_3010)
                    # Main dashboard frontend - uses relative paths for nginx proxy
                    cat > "$env_file" << EOF
# ============================================================================
# Dashboard Frontend (3010) Environment Variables
# ============================================================================
# Generated from web_services_config.yaml
# Environment: production
# ============================================================================

# Vite Configuration - Use relative paths for nginx proxy
VITE_API_URL=
VITE_WS_URL=/ws
VITE_AUTH_URL=
VITE_ENVIRONMENT=production
EOF
                    ;;

                auth_portal_4431)
                    # Auth portal frontend - uses relative paths for nginx proxy
                    cat > "$env_file" << EOF
# Auth Portal Frontend Environment
# Generated from web_services_config.yaml
# Environment: production
# Using relative paths (proxied by Nginx)
VITE_AUTH_URL=/auth
VITE_API_URL=/api
EOF
                    ;;

                vnc_service_8002)
                    # VNC service frontend - uses relative paths for nginx proxy
                    cat > "$env_file" << EOF
# VNC Service Frontend Environment
# Generated from web_services_config.yaml
# Environment: production
# Using relative paths (proxied by Nginx)
VITE_API_URL=/api
VITE_AUTH_URL=/auth
VITE_VNC_PROXY_URL=/vncproxy
EOF
                    ;;

                kooCAEWeb_5173)
                    # CAE web frontend - uses relative paths for nginx proxy
                    cat > "$env_file" << EOF
# CAE Web Frontend Environment
# Generated from web_services_config.yaml
# Environment: production
# Using relative paths (proxied by Nginx)
VITE_API_URL=/cae/api
VITE_AUTOMATION_URL=/cae/automation
VITE_AUTH_URL=/auth
VITE_ENVIRONMENT=production
EOF
                    ;;
            esac

            chmod 600 "$env_file"
            log_success ".env generated for $frontend (PUBLIC_URL=$PUBLIC_URL)"
        else
            log_info "[DRY-RUN] Would generate .env for $frontend"
        fi
    done

    log_success "All frontend .env files generated from YAML"
}

# Function to configure Auth Portal groups
# Updates GROUP_PERMISSIONS in auth_portal_4430/config/config.py
setup_auth_portal_groups() {
    local dashboard_dir=$1

    log_info "Configuring Auth Portal groups..."

    local config_file="$dashboard_dir/auth_portal_4430/config/config.py"

    if [[ ! -f "$config_file" ]]; then
        log_error "Auth Portal config not found: $config_file"
        return 1
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup original config
        cp "$config_file" "$config_file.backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Config backed up"

        # Update GROUP_PERMISSIONS using sed
        sed -i '/# Group-based permissions/,/^    }/c\
    # Group-based permissions\
    GROUP_PERMISSIONS = {\
        '\''HPC-Admins'\'': ['\''dashboard'\'', '\''cae'\'', '\''vnc'\'', '\''app'\'', '\''admin'\''],\
        '\''DX-Users'\'': ['\''dashboard'\'', '\''vnc'\'', '\''app'\''],\
        '\''CAEG-Users'\'': ['\''dashboard'\'', '\''cae'\'', '\''vnc'\'', '\''app'\''],\
    }' "$config_file"

        log_success "Auth Portal groups configured"
        log_info "  - HPC-Admins: Full access (admin included)"
        log_info "  - DX-Users: dashboard, vnc, app"
        log_info "  - CAEG-Users: dashboard, cae, vnc, app (admin excluded)"
    else
        log_info "[DRY-RUN] Would configure Auth Portal groups"
    fi
}

# Function to generate auth_portal_4430 .env file from YAML configuration
# Uses generate_sso_env.py script to create proper SSO configuration
generate_auth_portal_env() {
    local dashboard_dir=$1

    log_info "Generating Auth Portal (4430) .env file from YAML configuration..."

    local auth_portal_dir="$dashboard_dir/auth_portal_4430"
    local generate_script="$auth_portal_dir/generate_sso_env.py"

    if [[ ! -f "$generate_script" ]]; then
        log_warning "generate_sso_env.py not found: $generate_script"
        log_info "Falling back to manual .env generation..."

        if [[ "$DRY_RUN" == false ]]; then
            cat > "$auth_portal_dir/.env" << EOF
# Auth Portal SSO Configuration
# Generated by phase5_web.sh

# Flask Configuration
FLASK_DEBUG=False
SECRET_KEY=${JWT_SECRET_KEY:-change-this-secret-key}

# JWT Configuration
JWT_SECRET_KEY=${JWT_SECRET_KEY:-change-this-jwt-secret}
JWT_ALGORITHM=HS256
JWT_EXPIRATION_HOURS=8

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}

# SSO Configuration
SSO_ENABLED=${SSO_ENABLED:-false}
SSO_TYPE=${SSO_TYPE:-saml}

# Service URLs
DASHBOARD_URL=/dashboard
CAE_URL=/cae
VNC_URL=/vnc
APP_URL=/app

# Server
HOST=0.0.0.0
PORT=4430
EOF
            chmod 600 "$auth_portal_dir/.env"
            log_success "Auth Portal .env file created (fallback method)"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup existing .env if present
        if [[ -f "$auth_portal_dir/.env" ]]; then
            cp "$auth_portal_dir/.env" "$auth_portal_dir/.env.backup_$(date +%Y%m%d_%H%M%S)"
        fi

        # Generate .env using the Python script
        cd "$auth_portal_dir"
        python3 "$generate_script" --config "$CONFIG_PATH" --output ".env"

        if [[ $? -eq 0 && -f "$auth_portal_dir/.env" ]]; then
            chmod 600 "$auth_portal_dir/.env"
            log_success "Auth Portal .env file generated from YAML"
        else
            log_error "Failed to generate Auth Portal .env file"
            return 1
        fi
    else
        log_info "[DRY-RUN] Would generate Auth Portal .env from $CONFIG_PATH"
    fi
}

# Function to configure SAML IdP users for development
# Updates users.json in saml_idp_7000 with new group names
# Reads users from YAML config: web_services.saml.users[]
setup_saml_idp_users() {
    local dashboard_dir=$1

    log_info "Configuring SAML IdP test users..."

    local users_file="$dashboard_dir/saml_idp_7000/config/users.json"

    if [[ ! -f "$users_file" ]]; then
        log_warning "SAML IdP users.json not found: $users_file (skipping)"
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup original users file
        cp "$users_file" "$users_file.backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Users file backed up"

        # Read SAML users from YAML config, generate JSON
        # If not defined in YAML, use secure random passwords
        local saml_users_json
        saml_users_json=$(python3 << EOFPY
import yaml
import json
import secrets
import string

def generate_secure_password(length=16):
    """Generate a secure random password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    domain = config.get('cluster_info', {}).get('domain', 'hpc.local')
    saml_config = config.get('web_services', {}).get('saml', {})
    users = saml_config.get('users', [])
    if not users:
        users = config.get('saml', {}).get('test_users', []) or config.get('saml', {}).get('users', [])
    for u in users:
        if 'groups' not in u and 'roles' in u:
            role_map = {'admin': 'HPC-Admins', 'user': 'DX-Users', 'cae': 'CAEG-Users'}
            u['groups'] = sorted({role_map.get(r, r) for r in u['roles']})

    if not users:
        # No users defined - create default admin with secure random password
        admin_password = generate_secure_password()
        print(f"⚠️  YAML에 SAML 유저가 정의되지 않아 기본 admin 계정 생성", file=__import__('sys').stderr)
        print(f"   admin@{domain} 비밀번호: {admin_password}", file=__import__('sys').stderr)
        users = [{
            'username': 'admin',
            'password': admin_password,
            'first_name': 'System',
            'last_name': 'Admin',
            'display_name': 'System Administrator',
            'groups': ['HPC-Admins'],
            'department': 'IT'
        }]

    result = {}
    for user in users:
        username = user.get('username', 'user')
        email = f"{username}@{domain}"
        # Use password from YAML or generate secure one
        password = user.get('password')
        if not password or password in ['changeme', 'password123', 'admin123']:
            password = generate_secure_password()
            print(f"⚠️  {username}: 보안 비밀번호 자동생성됨 (YAML에 안전한 비밀번호 설정 권장)", file=__import__('sys').stderr)

        result[email] = {
            'password': password,
            'email': email,
            'userName': username,
            'firstName': user.get('first_name', username),
            'lastName': user.get('last_name', 'User'),
            'displayName': user.get('display_name', username),
            'groups': user.get('groups', ['Users']),
            'department': user.get('department', 'General')
        }

    print(json.dumps(result, indent=2, ensure_ascii=False))
except Exception as e:
    print(f"Error: {e}", file=__import__('sys').stderr)
    exit(1)
EOFPY
)
        if [[ $? -ne 0 ]]; then
            log_error "Failed to generate SAML users from YAML config"
            log_warning "Check web_services.saml.users in $CONFIG_PATH"
            return 1
        fi

        # Write users.json
        echo "$saml_users_json" > "$users_file"

        # Create config.js for saml-idp (JavaScript format required)
        # Generate dynamically from YAML config
        local config_js="$dashboard_dir/saml_idp_7000/config.js"
        python3 << EOFPY > "$config_js"
import yaml
import json
import secrets
import string

def generate_secure_password(length=16):
    alphabet = string.ascii_letters + string.digits + "!@#\$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    domain = config.get('cluster_info', {}).get('domain', 'hpc.local')
    saml_config = config.get('web_services', {}).get('saml', {})
    users = saml_config.get('users', [])
    if not users:
        users = config.get('saml', {}).get('test_users', []) or config.get('saml', {}).get('users', [])
    for u in users:
        if 'groups' not in u and 'roles' in u:
            role_map = {'admin': 'HPC-Admins', 'user': 'DX-Users', 'cae': 'CAEG-Users'}
            u['groups'] = sorted({role_map.get(r, r) for r in u['roles']})

    if not users:
        admin_password = generate_secure_password()
        users = [{
            'username': 'admin',
            'password': admin_password,
            'first_name': 'System',
            'last_name': 'Admin',
            'display_name': 'System Administrator',
            'groups': ['HPC-Admins'],
            'department': 'IT'
        }]

    print('/**')
    print(' * SAML IdP Configuration File')
    print(' * User database for authentication')
    print(' * Auto-generated from YAML config')
    print(' */')
    print('')
    print('module.exports = {')
    print('  user: {')

    user_entries = []
    for user in users:
        username = user.get('username', 'user')
        email = f"{username}@{domain}"
        password = user.get('password')
        if not password or password in ['changeme', 'password123', 'admin123']:
            password = generate_secure_password()

        groups = user.get('groups', ['Users'])
        if not isinstance(groups, list):
            groups = [groups]
        # ★다중 그룹을 JS 배열로 발급★ (기존 groups[0] 단일 문자열 버그 수정 — 역할/권한 모델은
        #  HPC-Admins/DX-Users 등 여러 그룹을 필요로 함). metadata 의 groups multiValue:true 와 짝.
        groups_js = '[' + ', '.join('"%s"' % g for g in groups) + ']'

        entry = f'''    "{email}": {{
      password: "{password}",
      email: "{email}",
      userName: "{username}",
      firstName: "{user.get('first_name', username)}",
      lastName: "{user.get('last_name', 'User')}",
      displayName: "{user.get('display_name', username)}",
      groups: {groups_js},
      department: "{user.get('department', 'General')}"
    }}'''
        user_entries.append(entry)

    print(',\\n'.join(user_entries))
    print('  },')
    print('  metadata: [')
    print('    {id: "email", optional: false, displayName: \'E-Mail Address\', description: \'The e-mail address of the user\', multiValue: false},')
    print('    {id: "userName", optional: false, displayName: \'User Name\', description: \'The username of the user\', multiValue: false},')
    print('    {id: "firstName", optional: false, displayName: \'First Name\', description: \'The first name of the user\', multiValue: false},')
    print('    {id: "lastName", optional: false, displayName: \'Last Name\', description: \'The last name of the user\', multiValue: false},')
    print('    {id: "displayName", optional: true, displayName: \'Display Name\', description: \'The display name of the user\', multiValue: false},')
    print('    {id: "groups", optional: true, displayName: \'Groups\', description: \'Group memberships of the user\', multiValue: true}')
    print('  ]')
    print('};')
except Exception as e:
    print(f"// Error generating config: {e}", file=__import__('sys').stderr)
    exit(1)
EOFPY

        if [[ $? -ne 0 ]]; then
            log_error "Failed to generate SAML config.js"
            return 1
        fi

        log_success "SAML IdP users configured from YAML (users.json + config.js)"
        log_info "  Users loaded from: $CONFIG_PATH (web_services.saml.users)"
    else
        log_info "[DRY-RUN] Would configure SAML IdP test users"
    fi
}

# Function to setup Python virtual environments for all services
# This function creates venvs with the correct Python version for each service
# and installs requirements from offline wheels
setup_python_venvs() {
    local dashboard_dir=$1
    local project_root="$(dirname "$dashboard_dir")"
    local wheels_base="${OFFLINE_PKG_DIR}/python_wheels"

    log_info "Setting up Python virtual environments for all services..."

    # Service to Python version mapping
    # Format: "service_name:python_version"
    # 24.04(noble)에서는 Python 3.10이 없으므로 3.12로 통합
    local py_legacy="3.10"
    if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
        py_legacy="3.12"
    fi
    local service_python_map=(
        "auth_portal_4430:${py_legacy}"
        "backend_5010:3.12"
        "websocket_5011:${py_legacy}"
        "kooCAEWebServer_5000:3.13"
        "kooCAEWebAutomationServer_5001:3.13"
        "MoonlightSunshine_8004/backend_moonlight_8004:${py_legacy}"
    )

    for mapping in "${service_python_map[@]}"; do
        local service="${mapping%%:*}"
        local py_version="${mapping##*:}"
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            log_warning "Service directory not found: $service, skipping..."
            continue
        fi

        log_info "Processing $service (Python $py_version)..."

        if [[ "$DRY_RUN" == false ]]; then
            # Determine Python command
            local python_cmd="python3"
            if command -v "python${py_version}" &>/dev/null; then
                python_cmd="python${py_version}"
            elif command -v "python3.${py_version#3.}" &>/dev/null; then
                python_cmd="python3.${py_version#3.}"
            fi

            # Create venv if not exists
            if [[ ! -d "$service_dir/venv" ]]; then
                log_info "  Creating venv with $python_cmd..."
                if ! $python_cmd -m venv "$service_dir/venv"; then
                    log_error "  Failed to create venv for $service"
                    continue
                fi
                log_success "  venv created"
            else
                log_info "  venv already exists"
            fi

            # Install requirements from offline wheels
            if [[ -f "$service_dir/requirements.txt" ]]; then
                cd "$service_dir"
                source venv/bin/activate

                # Get actual Python version in venv
                local actual_version=$(python --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "$py_version")
                local wheels_dir="${wheels_base}/python${actual_version}"

                log_info "  Installing requirements (wheels: python${actual_version})..."

                if [[ -d "$wheels_dir" ]]; then
                    local pip_log="/tmp/pip_${service}_$$.log"
                    # 부모 python_wheels도 같이 검색 (서비스별 휠이 부족할 때)
                    local parent_wheels="${wheels_base}"
                    if pip install --no-index --find-links="$wheels_dir" --find-links="$parent_wheels" -r requirements.txt >"$pip_log" 2>&1; then
                        log_success "  Requirements installed from offline wheels"
                        rm -f "$pip_log"
                    else
                        # 온라인 fallback 대신 누락 무시하고 부분 설치 시도 (--no-index 유지: PyPI 무한 retry 방지)
                        log_warning "  Offline install failed (일부 핀 불일치 가능) — 휠에 있는 것만 설치 시도"
                        # requirements.txt 한 줄씩 시도하여 가능한 모듈만 설치
                        local installed_count=0 failed_count=0
                        while IFS= read -r line; do
                            line=$(echo "$line" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                            [[ -z "$line" || "$line" == \#* ]] && continue
                            # 패키지 이름만 추출 (==, >=, <= 제거)
                            local pkg=$(echo "$line" | sed 's/[<>=!~].*//')
                            if pip install --no-index --find-links="$wheels_dir" --find-links="$parent_wheels" \
                                "$pkg" >>"$pip_log" 2>&1; then
                                installed_count=$((installed_count + 1))
                            else
                                failed_count=$((failed_count + 1))
                            fi
                        done < requirements.txt
                        log_info "  Partial install: ${installed_count} ok, ${failed_count} skipped"
                        log_info "  pip log: $pip_log (skip된 패키지 확인용)"
                    fi
                else
                    log_warning "  No offline wheels found at $wheels_dir"
                    log_warning "  Please prepare offline packages or install online"
                fi

                deactivate
                cd "$dashboard_dir"
            fi
        else
            log_info "[DRY-RUN] Would create venv and install requirements for $service"
        fi
    done

    log_success "Python virtual environments setup complete"
}

# Function to setup JWT authentication
# This function configures JWT-based authentication for all dashboard services
# Prerequisites:
#   - backend_5010/middleware/jwt_middleware.py must exist (source file)
#   - Auth Portal must be running with JWT_SECRET_KEY configured
# Services configured:
#   - kooCAEWebServer_5000 (App Framework API)
#   - backend_5010 (Dashboard Backend API - already has it)
#   - kooCAEWebAutomationServer_5001 (Automation API)
#   - websocket_5011 (WebSocket Service)
setup_jwt_authentication() {
    local dashboard_dir=$1

    log_info "Setting up JWT authentication..."

    # Check if source middleware exists
    local source_middleware="$dashboard_dir/backend_5010/middleware/jwt_middleware.py"
    if [[ ! -f "$source_middleware" ]]; then
        log_error "JWT middleware not found at $source_middleware"
        return 1
    fi

    log_success "Found JWT middleware source"

    # Services that need JWT authentication
    local services_with_jwt=(
        "kooCAEWebServer_5000"
        "kooCAEWebAutomationServer_5001"
        "websocket_5011"
    )

    for service in "${services_with_jwt[@]}"; do
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            log_warning "Service directory not found: $service_dir, skipping..."
            continue
        fi

        log_info "Installing JWT authentication in $service..."

        if [[ "$DRY_RUN" == false ]]; then
            # Create middleware directory
            mkdir -p "$service_dir/middleware"
            touch "$service_dir/middleware/__init__.py"

            # Copy JWT middleware
            cp "$source_middleware" "$service_dir/middleware/jwt_middleware.py"

            # Check if venv exists, create if not
            if [[ ! -d "$service_dir/venv" ]]; then
                log_info "Creating venv for $service..."
                # Determine Python version for each service
                local python_cmd="python3"
                case "$service" in
                    "backend_5010")
                        # Python 3.12 preferred
                        if command -v python3.12 &>/dev/null; then
                            python_cmd="python3.12"
                        fi
                        ;;
                    "kooCAEWebServer_5000"|"kooCAEWebAutomationServer_5001")
                        # Python 3.13 preferred
                        if command -v python3.13 &>/dev/null; then
                            python_cmd="python3.13"
                        elif command -v python3.12 &>/dev/null; then
                            python_cmd="python3.12"
                        fi
                        ;;
                    *)
                        # Default: Python 3.10
                        if command -v python3.10 &>/dev/null; then
                            python_cmd="python3.10"
                        fi
                        ;;
                esac

                log_info "  Using $python_cmd for $service"
                if ! $python_cmd -m venv "$service_dir/venv"; then
                    log_error "Failed to create venv for $service with $python_cmd"
                    continue
                fi
                log_success "venv created for $service"
            fi

            # Ensure PyJWT is in requirements.txt
            if [[ -f "$service_dir/requirements.txt" ]]; then
                if ! grep -q "PyJWT" "$service_dir/requirements.txt"; then
                    log_info "Adding PyJWT to $service requirements.txt"
                    echo "PyJWT>=2.8.0" >> "$service_dir/requirements.txt"
                fi
            fi

            # Install packages from requirements.txt (includes PyJWT)
            cd "$service_dir"
            if [[ -f "requirements.txt" ]]; then
                log_info "Installing packages from requirements.txt for $service..."
                source venv/bin/activate

                # Check if offline wheels are available
                # service_dir = /path/to/project/dashboard/service_name
                # project_root = /path/to/project (2 levels up)
                local project_root="$(dirname "$(dirname "$service_dir")")"
                local wheels_dir="${OFFLINE_PKG_DIR}/python_wheels"
                local py_version=$(python --version 2>&1 | grep -oP 'Python \K\d+\.\d+' || echo "3.12")
                local wheels_subdir="${wheels_dir}/python${py_version}"

                if [[ -d "$wheels_subdir" ]]; then
                    log_info "  Using offline wheels from $wheels_subdir (+ parent)"
                    # 부모 python_wheels 도 같이 검색 (서비스별 휠 누락 보완)
                    if ! pip install --no-index --find-links="$wheels_subdir" --find-links="$wheels_dir" -r requirements.txt --quiet; then
                        log_warning "전체 requirements 실패 → 한 줄씩 부분 설치 시도 (--no-index 유지, PyPI 무한 retry 차단)"
                        local _ok=0 _fail=0
                        while IFS= read -r _line; do
                            _line=$(echo "$_line" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                            [[ -z "$_line" || "$_line" == \#* ]] && continue
                            local _pkg=$(echo "$_line" | sed 's/[<>=!~].*//')
                            if pip install --no-index --find-links="$wheels_subdir" --find-links="$wheels_dir" \
                                "$_pkg" --quiet 2>/dev/null; then
                                _ok=$((_ok + 1))
                            else
                                _fail=$((_fail + 1))
                            fi
                        done < requirements.txt
                        log_info "  Partial install: ${_ok} 성공, ${_fail} 스킵"
                        if [[ "$_ok" -eq 0 ]]; then
                            log_error "CRITICAL: 휠 디렉토리 자체가 비었거나 매칭 안 됨: $wheels_subdir"
                            deactivate
                            exit 1
                        fi
                    fi
                else
                    log_info "  No offline wheels found, installing from PyPI..."
                    if ! pip install -r requirements.txt --quiet; then
                        log_error "CRITICAL: Failed to install requirements for $service from PyPI"
                        log_error "Requirements file: $service_dir/requirements.txt"
                        log_error "This is an OFFLINE installation - PyPI is not accessible!"
                        echo ""
                        log_error "Expected offline wheels location: $wheels_subdir"
                        log_error "Please ensure offline packages are prepared:"
                        log_error "  1. Run download_python_wheels.sh on an online machine"
                        log_error "  2. Copy offline packages directory to the offline server"
                        echo ""
                        log_error "--- pip install output ---"
                        pip install -r requirements.txt 2>&1 | tail -50 || true
                        echo ""
                        deactivate
                        exit 1
                    fi
                fi

                deactivate
            fi

            # Add JWT configuration to .env
            # Use JWT_SECRET from YAML config, fallback to default
            local jwt_value="${JWT_SECRET:-dev-jwt-secret-please-change}"

            if [[ -f "$service_dir/.env" ]]; then
                if ! grep -q "^JWT_SECRET_KEY=" "$service_dir/.env"; then
                    echo "" >> "$service_dir/.env"
                    echo "# JWT Configuration (must match Auth Portal)" >> "$service_dir/.env"
                    echo "JWT_SECRET_KEY=${jwt_value}" >> "$service_dir/.env"
                    echo "JWT_ALGORITHM=HS256" >> "$service_dir/.env"
                    log_success "JWT configuration added to .env"
                elif [[ -n "$JWT_SECRET" && "$JWT_SECRET" != "change-this-jwt-secret" ]]; then
                    # Update existing JWT_SECRET_KEY if YAML provides a real value
                    sed -i "s/^JWT_SECRET_KEY=.*/JWT_SECRET_KEY=${jwt_value}/" "$service_dir/.env"
                    log_info "JWT_SECRET_KEY updated from YAML config"
                else
                    log_info "JWT configuration already exists in .env"
                fi
            else
                cat > "$service_dir/.env" << EOF
# JWT Configuration (must match Auth Portal)
JWT_SECRET_KEY=${jwt_value}
JWT_ALGORITHM=HS256
EOF
                # Set ownership (use service_user from YAML or current user)
                local jwt_owner="${SERVICE_USER:-$(whoami)}"
                local jwt_group="${SERVICE_GROUP:-$(id -gn)}"
                if [[ -f "$CONFIG_PATH" ]]; then
                    local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    [[ -n "$yaml_user" ]] && jwt_owner="$yaml_user"
                    [[ -n "$yaml_group" ]] && jwt_group="$yaml_group"
                fi
                chown "$jwt_owner:$jwt_group" "$service_dir/.env"
                log_success ".env file created with JWT configuration"
            fi

            log_success "JWT authentication setup completed for $service"
        else
            log_info "[DRY-RUN] Would install JWT authentication in $service"
        fi
    done

    log_success "JWT authentication setup complete"
}

# Function to run database migrations for backend services
# This creates necessary tables (apptainer_images, templates, etc.)
run_database_migrations() {
    local dashboard_dir=$1

    log_info "Running database migrations for backend services..."

    local backend_dir="$dashboard_dir/backend_5010"
    local migration_script="$backend_dir/run_migrations.py"

    if [[ ! -f "$migration_script" ]]; then
        log_warning "Migration script not found: $migration_script"
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Get database path from .env or use default
        local db_path
        if [[ -f "$backend_dir/.env" ]]; then
            db_path=$(grep "^DATABASE_PATH=" "$backend_dir/.env" 2>/dev/null | cut -d= -f2)
        fi
        # Use backend_5010/database/dashboard.db as default (matches database.py)
        db_path="${db_path:-$backend_dir/database/dashboard.db}"

        # Create DB directory if not exists
        local db_dir=$(dirname "$db_path")
        if [[ ! -d "$db_dir" ]]; then
            log_info "Creating database directory: $db_dir"
            mkdir -p "$db_dir"
            # Set ownership (use service_user from YAML or current user)
            local db_owner="${SERVICE_USER:-$(whoami)}"
            local db_group="${SERVICE_GROUP:-$(id -gn)}"
            if [[ -f "$CONFIG_PATH" ]]; then
                local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                [[ -n "$yaml_user" ]] && db_owner="$yaml_user"
                [[ -n "$yaml_group" ]] && db_group="$yaml_group"
            fi
            chown "$db_owner:$db_group" "$db_dir"
        fi

        # Run migrations using venv Python
        cd "$backend_dir"
        if [[ -f "venv/bin/activate" ]]; then
            log_info "Running migrations with venv Python..."
            (
                source venv/bin/activate
                python3 run_migrations.py --db-path "$db_path" 2>&1 | while read -r line; do
                    log_info "  $line"
                done
                deactivate
            )

            if [[ -f "$db_path" ]]; then
                # Set DB file ownership
                local db_owner="${SERVICE_USER:-$(whoami)}"
                local db_group="${SERVICE_GROUP:-$(id -gn)}"
                if [[ -f "$CONFIG_PATH" ]]; then
                    local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    local yaml_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                    [[ -n "$yaml_user" ]] && db_owner="$yaml_user"
                    [[ -n "$yaml_group" ]] && db_group="$yaml_group"
                fi
                chown "$db_owner:$db_group" "$db_path"
                log_success "Database migrations completed: $db_path"
            else
                log_warning "Database file not created: $db_path"
            fi
        else
            log_warning "venv not found for backend_5010, skipping migrations"
        fi
    else
        log_info "[DRY-RUN] Would run database migrations"
    fi
}

# Function to initialize template storage (/shared/templates/)
# Copies templates from dashboard/templates/ and creates sample templates
init_template_storage() {
    log_info "Initializing template storage (/shared/templates/)..."

    local init_script="$SCRIPT_DIR/init_template_storage.sh"

    if [[ ! -f "$init_script" ]]; then
        log_warning "Template init script not found: $init_script"
        log_info "Skipping template storage initialization"
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Check if /shared exists (it should exist if GlusterFS is mounted or local)
        if [[ -d "/shared" ]] || [[ -L "/shared" ]]; then
            log_info "Running template storage initialization..."
            bash "$init_script" 2>&1 | while read -r line; do
                log_info "  $line"
            done
            log_success "Template storage initialized"
        else
            log_warning "/shared directory not found, skipping template storage initialization"
            log_info "You can manually run: sudo $init_script"
        fi
    else
        log_info "[DRY-RUN] Would run template storage initialization"
    fi
}

# Function to setup sudoers for web service user
# Allows web services to run Slurm commands without password
setup_web_sudoers() {
    log_info "Setting up sudoers for web service user..."

    # Get service user from YAML or use default
    local service_user="${SERVICE_USER:-$(whoami)}"
    if [[ -f "$CONFIG_PATH" ]]; then
        local yaml_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
        [[ -n "$yaml_user" ]] && service_user="$yaml_user"
    fi

    # Skip if running as root (root doesn't need sudoers)
    if [[ "$service_user" == "root" ]]; then
        log_info "Service user is root, skipping sudoers setup"
        return 0
    fi

    local sudoers_file="/etc/sudoers.d/hpc-web-services"

    if [[ "$DRY_RUN" == false ]]; then
        # Create sudoers file for web service user
        cat > "$sudoers_file" << EOF
# HPC Web Services - Slurm command permissions
# Generated by phase5_web.sh
# Allows web service user to run Slurm admin commands without password

# Slurm commands (absolute paths)
${service_user} ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/scontrol
${service_user} ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/sacctmgr
${service_user} ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/squeue
${service_user} ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/sinfo
${service_user} ALL=(ALL) NOPASSWD: /usr/local/slurm/bin/scancel

# Slurm config management
${service_user} ALL=(ALL) NOPASSWD: /bin/cp /etc/slurm/slurm.conf*
${service_user} ALL=(ALL) NOPASSWD: /bin/cat /etc/slurm/slurm.conf

# System commands for node management
${service_user} ALL=(ALL) NOPASSWD: /bin/systemctl restart slurmctld
${service_user} ALL=(ALL) NOPASSWD: /bin/systemctl reload slurmctld
EOF

        # Set correct permissions (sudoers files must be 0440)
        chmod 0440 "$sudoers_file"

        # Validate sudoers syntax
        if visudo -c -f "$sudoers_file" 2>/dev/null; then
            log_success "Sudoers file created: $sudoers_file"
            log_info "User '$service_user' can now run Slurm commands with sudo"
        else
            log_error "Invalid sudoers syntax, removing file"
            rm -f "$sudoers_file"
            return 1
        fi
    else
        log_info "[DRY-RUN] Would create sudoers file: $sudoers_file"
    fi
}

# Function to initialize cluster_config from YAML partitions
init_cluster_config_from_yaml() {
    local dashboard_dir=$1

    log_info "Initializing cluster_config from YAML partitions..."

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_warning "Config file not found: $CONFIG_PATH"
        return 0
    fi

    local backend_dir="$dashboard_dir/backend_5010"
    local db_path
    if [[ -f "$backend_dir/.env" ]]; then
        db_path=$(grep "^DATABASE_PATH=" "$backend_dir/.env" 2>/dev/null | cut -d= -f2)
    fi
    # Use backend_5010/database/dashboard.db as default (matches database.py)
    db_path="${db_path:-$backend_dir/database/dashboard.db}"

    if [[ "$DRY_RUN" == false ]]; then
        # Parse YAML and generate cluster_config JSON
        local cluster_config_json
        cluster_config_json=$(python3 << EOPY
import yaml
import json
import sys

try:
    with open('$CONFIG_PATH', 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"Error reading YAML: {e}", file=sys.stderr)
    sys.exit(1)

# Get compute nodes from YAML for hardware info lookup
compute_nodes = config.get('nodes', {}).get('compute_nodes', [])
viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
all_nodes = compute_nodes + viz_nodes

# Create hostname -> hardware info mapping
node_hardware = {}
for node in all_nodes:
    hostname = node.get('hostname')
    if hostname:
        node_hardware[hostname] = {
            'ip_address': node.get('ip_address'),
            'cpus': node.get('hardware', {}).get('cpus', 128),
            'memory_mb': node.get('hardware', {}).get('memory_mb', 0)
        }

# Get partitions from YAML (check multiple locations)
# Priority: slurm_config.partitions > slurm.partitions > partitions (root)
partitions = config.get('slurm_config', {}).get('partitions', [])
if not partitions:
    partitions = config.get('slurm', {}).get('partitions', [])
if not partitions:
    partitions = config.get('partitions', [])

# Create groups from partitions using actual hostnames from YAML partitions.nodes
groups = []
colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16']

for idx, partition in enumerate(partitions):
    partition_name = partition.get('name', f'partition{idx+1}')
    nodes_str = partition.get('nodes', '')

    # Parse comma-separated hostname list from YAML partitions.nodes
    node_list = []
    if nodes_str:
        for hostname in nodes_str.split(','):
            hostname = hostname.strip()
            if hostname:
                hw = node_hardware.get(hostname, {})
                node_list.append({
                    'hostname': hostname,
                    'ip_address': hw.get('ip_address', ''),
                    'cpus': hw.get('cpus', 128),
                    'memory_mb': hw.get('memory_mb', 0),
                    'status': 'idle'
                })

    # Calculate total cores from actual hardware info
    total_cores = sum(n.get('cpus', 128) for n in node_list)

    group = {
        'id': idx + 1,
        'name': partition_name.capitalize(),
        'partitionName': partition_name,
        'qosName': f'{partition_name}_qos',
        'allowedCoreSizes': [32, 64, 128],  # Default
        'color': colors[idx % len(colors)],
        'description': partition.get('description', f'{partition_name} partition'),
        'nodeCount': len(node_list),
        'totalCores': total_cores,
        'nodes': node_list,
        'maxTime': partition.get('max_time', 'INFINITE'),
        'default': partition.get('default', False)
    }
    groups.append(group)
    print(f"Partition '{partition_name}' -> {len(node_list)} nodes", file=sys.stderr)

# Get cluster info
cluster_info = config.get('cluster_info', {})
cluster_name = cluster_info.get('cluster_name', 'HPC-Cluster')

# Get controller IP
controllers = config.get('nodes', {}).get('controllers', [])
controller_ip = controllers[0].get('ip_address', '127.0.0.1') if controllers else '127.0.0.1'

# Calculate totals
total_nodes = sum(g['nodeCount'] for g in groups)
total_cores = sum(g['totalCores'] for g in groups)

cluster_config = {
    'groups': groups,
    'clusterName': cluster_name,
    'controllerIp': controller_ip,
    'totalNodes': total_nodes,
    'totalCores': total_cores
}

print(json.dumps(cluster_config))
EOPY
        )

        if [[ $? -ne 0 ]] || [[ -z "$cluster_config_json" ]]; then
            log_warning "Failed to parse partitions from YAML"
            return 0
        fi

        # Update cluster_config in database
        log_info "Updating cluster_config in database..."
        python3 << EOPY
import sqlite3
import json
import sys

db_path = '$db_path'
config_json = '''$cluster_config_json'''

try:
    config = json.loads(config_json)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if cluster_config table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cluster_config'")
    if not cursor.fetchone():
        print("cluster_config table not found, skipping", file=sys.stderr)
        sys.exit(0)

    # Update or insert
    cursor.execute("SELECT id FROM cluster_config WHERE id = 1")
    if cursor.fetchone():
        cursor.execute("""
            UPDATE cluster_config
            SET config = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = 1
        """, (json.dumps(config),))
        print(f"Updated cluster_config with {len(config.get('groups', []))} groups")
    else:
        cursor.execute("""
            INSERT INTO cluster_config (id, config)
            VALUES (1, ?)
        """, (json.dumps(config),))
        print(f"Inserted cluster_config with {len(config.get('groups', []))} groups")

    conn.commit()
    conn.close()
except Exception as e:
    print(f"Error updating database: {e}", file=sys.stderr)
    sys.exit(1)
EOPY

        if [[ $? -eq 0 ]]; then
            log_success "Cluster config initialized from YAML partitions"
        else
            log_warning "Failed to initialize cluster config"
        fi
    else
        log_info "[DRY-RUN] Would initialize cluster_config from YAML"
    fi
}

# Function to deploy all web services
deploy_web_services() {
    log_info "Setting up web services from dashboard source..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    if [[ ! -d "$dashboard_dir" ]]; then
        log_error "Dashboard directory not found: $dashboard_dir"
        return 1
    fi

    log_info "Using dashboard directory: $dashboard_dir"
    log_info "Services will run directly from dashboard with existing venv"

    # Generate frontend .env files from YAML (must be done BEFORE building)
    generate_frontend_env_files "$dashboard_dir"

    # Setup Auth Portal groups
    setup_auth_portal_groups "$dashboard_dir"

    # Generate Auth Portal (4430) .env file from YAML
    generate_auth_portal_env "$dashboard_dir"

    # Setup SAML IdP test users (creates config.js)
    setup_saml_idp_users "$dashboard_dir"

    # Setup Python virtual environments and install requirements
    setup_python_venvs "$dashboard_dir"

    # Run database migrations (creates apptainer_images, templates tables, etc.)
    run_database_migrations "$dashboard_dir"

    # Initialize template storage (/shared/templates/)
    init_template_storage

    # Initialize cluster_config from YAML partitions (replaces hardcoded defaults)
    init_cluster_config_from_yaml "$dashboard_dir"

    # Setup Redis session management
    setup_redis_session_management "$dashboard_dir"

    # Setup JWT authentication
    setup_jwt_authentication "$dashboard_dir"

    # Setup sudoers for web service user (Slurm commands)
    setup_web_sudoers

    log_success "Web services setup complete (13 services configured)"
}

# Function to create systemd service file
create_systemd_service() {
    local service_name=$1
    local service_type=$2  # python or node
    local port=$3
    local start_command=$4

    log_info "Creating systemd service for $service_name ($service_type)..."

    local service_file="/etc/systemd/system/$service_name.service"
    local work_dir="$WEB_SERVICES_DIR/$service_name"

    if [[ "$DRY_RUN" == false ]]; then
        # YAML에서 service_user/service_group 읽기 (기본값: 현재 사용자)
        local service_user="${SERVICE_USER:-$(whoami)}"
        local service_group="${SERVICE_GROUP:-$(id -gn)}"
        if [[ -f "$CONFIG_PATH" ]]; then
            local yaml_service_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            local yaml_service_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            if [[ -n "$yaml_service_user" ]]; then
                service_user="$yaml_service_user"
            fi
            if [[ -n "$yaml_service_group" ]]; then
                service_group="$yaml_service_group"
            fi
        fi

        # Different ExecStart based on service type
        local exec_start=""
        local environment=""

        if [[ "$service_type" == "python" ]]; then
            # Python services: use bash to activate venv
            exec_start="/bin/bash -c 'cd $work_dir && $start_command'"
            environment="Environment=\"MOCK_MODE=false\"\nEnvironment=\"PORT=$port\"\nEnvironmentFile=-$work_dir/.env"
        else
            # Node services
            exec_start="/bin/bash -c 'cd $work_dir && $start_command'"
            environment="Environment=\"NODE_ENV=development\"\nEnvironment=\"PORT=$port\"\nEnvironmentFile=-$work_dir/.env"
        fi

        cat > "$service_file" << EOF
[Unit]
Description=$service_name - Web Service ($service_type)
After=network.target mariadb.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=$service_user
Group=$service_group
WorkingDirectory=$work_dir

# Environment
$(echo -e "$environment")

# Start command
ExecStart=$exec_start

# Restart policy
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=10

# Resource limits
MemoryLimit=2G
CPUQuota=200%

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$work_dir $work_dir/logs /var/log/web_services /tmp

# Logging
StandardOutput=append:/var/log/web_services/$service_name.log
StandardError=append:/var/log/web_services/$service_name.error.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        log_success "Systemd service created: $service_name"
    else
        log_info "[DRY-RUN] Would create systemd service: $service_name"
    fi
}

# Function to apply JWT authentication fixes to CAE frontend
apply_cae_jwt_fixes() {
    local cae_dir="$1"
    log_info "Applying JWT authentication fixes to CAE frontend..."

    # Fix 1: Update App.tsx - Add JWT token reception from URL
    local app_tsx="$cae_dir/src/App.tsx"
    if [[ -f "$app_tsx" ]]; then
        # Check if JWT reception code already exists
        if grep -q "JWT token received from URL" "$app_tsx"; then
            log_info "App.tsx already has JWT token reception"
        else
            log_info "Adding JWT token reception to App.tsx..."
            # Add useEffect import if not present
            if ! grep -q "import.*useEffect.*from 'react'" "$app_tsx"; then
                sed -i "s/from 'react';/{ useEffect } from 'react';/" "$app_tsx"
            fi

            # Add JWT reception logic after function App() {
            sed -i '/function App() {/a\
  useEffect(() => {\
    // Extract JWT token from URL query parameters (from Auth Portal)\
    const urlParams = new URLSearchParams(window.location.search);\
    const token = urlParams.get('\''token'\'');\
\
    if (token) {\
      console.log('\''[CAE Auth] JWT token received from URL, storing in localStorage'\'');\
      localStorage.setItem('\''jwt_token'\'', token);\
\
      // Remove token from URL for security\
      window.history.replaceState({}, document.title, window.location.pathname);\
\
      // Reload to apply authentication\
      window.location.reload();\
    }\
  }, []);' "$app_tsx"
            log_success "JWT token reception added to App.tsx"
        fi
    fi

    # Fix 2: Update axiosClient.ts - Change baseURL and add JWT interceptors
    local axios_client="$cae_dir/src/api/axiosClient.ts"
    if [[ -f "$axios_client" ]]; then
        # Check if JWT interceptor already exists
        if grep -q "CAE API.*Request with JWT token" "$axios_client"; then
            log_info "axiosClient.ts already has JWT interceptor"
        else
            log_info "Adding JWT interceptor to axiosClient.ts..."

            # Replace the entire file content
            cat > "$axios_client" << 'AXIOS_EOF'
import axios from 'axios';

// Use relative path for Nginx routing: /cae/automation/ -> http://localhost:5001/
const baseURL = '/cae/automation';

export const api = axios.create({
  baseURL,
});

// Request interceptor: Add JWT token to all requests
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('jwt_token');

    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
      console.log('[CAE API] Request with JWT token:', config.url);
    } else {
      console.warn('[CAE API] Request without JWT token:', config.url);
    }

    return config;
  },
  (error) => {
    console.error('[CAE API] Request error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor: Handle 401 errors
api.interceptors.response.use(
  (response) => {
    console.log('[CAE API] Response success:', response.config.url, response.status);
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      console.error('[CAE API] 401 Unauthorized - Token invalid or expired');

      // Clear invalid token
      localStorage.removeItem('jwt_token');

      // Redirect to Auth Portal
      console.log('[CAE API] Redirecting to Auth Portal...');
      window.location.href = '/';
    } else if (error.response) {
      console.error('[CAE API] Response error:', error.response.status, error.response.data);
    } else if (error.request) {
      console.error('[CAE API] No response received:', error.request);
    } else {
      console.error('[CAE API] Error:', error.message);
    }

    return Promise.reject(error);
  }
);
AXIOS_EOF
            log_success "JWT interceptor added to axiosClient.ts"
        fi
    fi

    # Fix 3: Update FileTreeExplorer.tsx - Remove automationApi, use shared api
    local file_explorer="$cae_dir/src/components/common/FileTreeExplorer.tsx"
    if [[ -f "$file_explorer" ]]; then
        if grep -q "automationApi" "$file_explorer"; then
            log_info "Fixing FileTreeExplorer.tsx to use shared axios instance..."

            # Remove axios and API_CONFIG imports
            sed -i '/import axios from .axios.;/d' "$file_explorer"
            sed -i '/import.*API_CONFIG.*from/d' "$file_explorer"

            # Remove automationApi creation
            sed -i '/const automationApi = useMemo.*axios\.create/,/}), \[\]);/d' "$file_explorer"

            # Replace all automationApi with api
            sed -i 's/automationApi/api/g' "$file_explorer"

            log_success "FileTreeExplorer.tsx fixed to use shared axios instance"
        else
            log_info "FileTreeExplorer.tsx already using shared axios instance"
        fi
    fi

    # Fix 4: Update FileTreeTextBox.tsx - Remove automationApi, use shared api
    local file_textbox="$cae_dir/src/components/common/FileTreeTextBox.tsx"
    if [[ -f "$file_textbox" ]]; then
        if grep -q "automationApi" "$file_textbox"; then
            log_info "Fixing FileTreeTextBox.tsx to use shared axios instance..."

            # Remove axios and API_CONFIG imports, add api import if not present
            sed -i '/import axios from .axios.;/d' "$file_textbox"
            sed -i '/import.*API_CONFIG.*from/d' "$file_textbox"

            # Add api import if not present
            if ! grep -q "import.*api.*from.*api/axiosClient" "$file_textbox"; then
                sed -i '/^import React/a import { api } from '\''../../api/axiosClient'\'';' "$file_textbox"
            fi

            # Remove automationApi creation and useMemo if only used for that
            sed -i '/const automationApi = useMemo.*axios\.create/,/}), \[\]);/d' "$file_textbox"

            # Replace all automationApi with api
            sed -i 's/automationApi/api/g' "$file_textbox"

            # Remove useMemo from imports if it's no longer used
            if ! grep -q "useMemo" "$file_textbox" 2>/dev/null; then
                sed -i 's/, useMemo//' "$file_textbox"
                sed -i 's/useMemo, //' "$file_textbox"
            fi

            log_success "FileTreeTextBox.tsx fixed to use shared axios instance"
        else
            log_info "FileTreeTextBox.tsx already using shared axios instance"
        fi
    fi

    log_success "All JWT authentication fixes applied to CAE frontend"
}

# Function to build all frontend services
build_all_frontends() {
    log_info "Building frontend services for production..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"
    local frontends=(
        "frontend_3010"
        "auth_portal_4431"
        "kooCAEWeb_5173"
        "app_5174"
        "vnc_service_8002"
    )

    for frontend in "${frontends[@]}"; do
        local frontend_dir="$dashboard_dir/$frontend"

        if [[ -d "$frontend_dir" ]]; then
            log_info "Building $frontend..."

            if [[ "$DRY_RUN" == false ]]; then
                # Apply JWT authentication fixes for CAE frontend BEFORE building
                if [[ "$frontend" == "kooCAEWeb_5173" ]]; then
                    apply_cae_jwt_fixes "$frontend_dir"
                fi

                cd "$frontend_dir"

                # Install dependencies if needed (check for critical packages too)
                local need_install=false
                if [[ ! -d "node_modules" ]]; then
                    need_install=true
                    log_info "node_modules not found for $frontend"
                elif [[ "$frontend" == "kooCAEWeb_5173" ]]; then
                    # Check critical dependencies for CAE frontend
                    if [[ ! -d "node_modules/@mui/material" ]] || [[ ! -d "node_modules/@mui/icons-material" ]]; then
                        need_install=true
                        log_info "Critical MUI packages missing in $frontend"
                    fi
                fi

                if [[ "$need_install" == true ]]; then
                    log_info "Installing dependencies for $frontend..."
                    npm install || log_warning "npm install failed for $frontend"
                fi

                # Build frontend with retry on module errors
                if ! npm run build 2>&1 | tee /tmp/${frontend}_build.log; then
                    log_warning "Build failed for $frontend, checking for module errors..."
                    if grep -q "Cannot find module" /tmp/${frontend}_build.log 2>/dev/null; then
                        log_info "Module missing detected, reinstalling dependencies..."
                        rm -rf node_modules 2>/dev/null || true
                        npm install
                        npm run build || log_warning "Rebuild failed for $frontend"
                    else
                        log_warning "Build failed for $frontend (non-module error)"
                    fi
                fi

                # Special handling for app_5174: copy landing.html to dist/index.html
                if [[ "$frontend" == "app_5174" && -f "landing.html" ]]; then
                    cp landing.html dist/index.html
                    log_info "Copied landing.html to dist/index.html for app_5174"
                fi

                # Apply GEdit fixes (single window.open, longer VNC wait time)
                if [[ "$frontend" == "app_5174" ]]; then
                    local gedit_html="dist/apps/gedit/index.html"
                    if [[ -f "$gedit_html" ]]; then
                        # Check if it has the old multiple window.open issue
                        if grep -q "windowOpened" "$gedit_html"; then
                            log_info "GEdit already has single window.open fix applied"
                        else
                            log_warning "GEdit needs update - applying single window.open fix"
                            # Note: The fix should be applied to source file in dashboard/app_5174/apps/gedit/index.html
                            # This built version will be replaced on next build
                        fi
                    fi
                fi

                # Create nginx serve directory
                local nginx_dir="/var/www/html/$frontend"
                mkdir -p "$nginx_dir"

                # Copy dist to nginx directory
                if [[ -d "dist" ]]; then
                    cp -r dist/* "$nginx_dir/"
                    log_success "$frontend built and copied to $nginx_dir"

                    # Handle Nginx alias mappings (source_dir → nginx_alias)
                    # These frontends need to be copied to both their original name AND the Nginx alias
                    case "$frontend" in
                        frontend_3010)
                            # /dashboard → /var/www/html/dashboard (Nginx serves this)
                            local alias_dir="/var/www/html/dashboard"
                            mkdir -p "$alias_dir"
                            cp -r dist/* "$alias_dir/"
                            log_success "$frontend also copied to $alias_dir (Nginx alias: /dashboard)"
                            ;;
                        kooCAEWeb_5173)
                            # /cae → /var/www/html/cae (Nginx serves this)
                            local alias_dir="/var/www/html/cae"
                            mkdir -p "$alias_dir"
                            cp -r dist/* "$alias_dir/"
                            log_success "$frontend also copied to $alias_dir (Nginx alias: /cae)"
                            ;;
                        # vnc_service_8002 and app_5174 already match their Nginx paths
                    esac
                else
                    log_warning "No dist directory found for $frontend"
                fi

                cd "$PROJECT_ROOT"
            else
                log_info "[DRY-RUN] Would build $frontend"
            fi
        else
            log_warning "Frontend directory not found: $frontend_dir"
        fi
    done

    # Set proper permissions on /var/www/html for nginx access
    if [[ "$DRY_RUN" == false ]]; then
        log_info "Setting permissions on /var/www/html for nginx access..."
        if [[ -d "/var/www/html" ]]; then
            chown -R www-data:www-data /var/www/html 2>/dev/null || chown -R nginx:nginx /var/www/html 2>/dev/null || true
            chmod -R 755 /var/www/html 2>/dev/null || true
            log_success "Permissions set on /var/www/html"
        fi
    fi

    log_success "All frontends built"
}

# Function to create all systemd services
create_systemd_services() {
    log_info "Creating systemd services for production mode..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    # Verify Python venv existence for all services
    log_info "Verifying Python virtual environments..."
    local python_services=(
        "auth_portal_4430"
        "backend_5010"
        "websocket_5011"
        "kooCAEWebServer_5000"
        "kooCAEWebAutomationServer_5001"
    )

    local venv_missing=false
    for service in "${python_services[@]}"; do
        local service_dir="$dashboard_dir/$service"
        if [[ ! -f "$service_dir/venv/bin/activate" ]]; then
            log_error "CRITICAL: Python venv not found for $service"
            log_error "Expected: $service_dir/venv/bin/activate"
            venv_missing=true
        else
            log_success "✓ venv exists for $service"
        fi
    done

    if [[ "$venv_missing" == true ]]; then
        echo ""
        log_error "Python virtual environments are missing!"
        log_error "Please ensure all services have been set up correctly."
        log_error "Check if previous installation steps completed successfully."
        exit 1
    fi

    # Python Backend Services (5)
    create_systemd_service_direct "auth_backend" "python" 4430 "$dashboard_dir/auth_portal_4430" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "dashboard_backend" "python" 5010 "$dashboard_dir/backend_5010" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "websocket_service" "python" 5011 "$dashboard_dir/websocket_5011" "source venv/bin/activate && python3 websocket_server_enhanced.py"
    create_systemd_service_direct "cae_backend" "python" 5000 "$dashboard_dir/kooCAEWebServer_5000" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "cae_automation" "python" 5001 "$dashboard_dir/kooCAEWebAutomationServer_5001" "source venv/bin/activate && python3 app.py"

    # Note: auth_portal_4431 is built by build_all_frontends() and served by Nginx (no systemd service needed)

    # Monitoring Services (3)
    create_systemd_service_direct "saml_idp" "node" 7000 "$dashboard_dir/saml_idp_7000" "npx saml-idp --port 7000 --host 0.0.0.0 --issuer \"http://localhost:7000/metadata\" --acsUrl \"http://localhost:4430/auth/saml/acs\" --audience \"auth-portal\" --cert \"certs/idp-cert.pem\" --key \"certs/idp-key.pem\" --configFile \"$dashboard_dir/saml_idp_7000/config.js\""
    create_systemd_service_direct "prometheus" "monitoring" 9090 "$dashboard_dir/prometheus_9090" "./prometheus --config.file=prometheus.yml --storage.tsdb.path=./data"
    create_systemd_service_direct "node_exporter" "monitoring" 9100 "$dashboard_dir/node_exporter_9100" "./node_exporter"

    log_success "All systemd services created (Production mode: backends only, frontends served by Nginx)"
}

# Function to create systemd service directly with full path
create_systemd_service_direct() {
    local service_name=$1
    local service_type=$2
    local port=$3
    local work_dir=$4
    local start_command=$5

    log_info "Creating systemd service for $service_name..."

    local service_file="/etc/systemd/system/$service_name.service"

    if [[ "$DRY_RUN" == false ]]; then
        local environment=""

        # SSO 설정 가져오기 (환경변수 또는 기본값)
        local sso_enabled="${SSO_ENABLED:-true}"

        # YAML에서 service_user/service_group 읽기 (기본값: 현재 사용자)
        local service_user="${SERVICE_USER:-$(whoami)}"
        local service_group="${SERVICE_GROUP:-$(id -gn)}"
        if [[ -f "$CONFIG_PATH" ]]; then
            local yaml_service_user=$(grep -E "^\s+service_user:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            local yaml_service_group=$(grep -E "^\s+service_group:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            if [[ -n "$yaml_service_user" ]]; then
                service_user="$yaml_service_user"
            fi
            if [[ -n "$yaml_service_group" ]]; then
                service_group="$yaml_service_group"
            fi
        fi

        # YAML에서 Slurm 경로 읽기 (우선순위: bin_path > install_path/bin > 기본값)
        # 기본값: /usr/local/slurm/bin (Slurm 23.11.10 소스 빌드)
        local slurm_bin_path="/usr/local/slurm/bin"
        local slurm_sbin_path="/usr/local/slurm/sbin"
        if [[ -f "$CONFIG_PATH" ]]; then
            # 1. bin_path 직접 지정 확인
            local yaml_bin_path=$(grep -E "^\s+bin_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
            if [[ -n "$yaml_bin_path" ]]; then
                slurm_bin_path="$yaml_bin_path"
                slurm_sbin_path="${yaml_bin_path%/bin}/sbin"
            else
                # 2. install_path에서 유도 (slurm_config.install_path)
                local yaml_install_path=$(grep -E "^\s+install_path:" "$CONFIG_PATH" 2>/dev/null | head -1 | awk '{print $2}')
                if [[ -n "$yaml_install_path" ]]; then
                    slurm_bin_path="${yaml_install_path}/bin"
                    slurm_sbin_path="${yaml_install_path}/sbin"
                fi
            fi
        fi
        log_info "Slurm bin path: $slurm_bin_path"

        if [[ "$service_type" == "python" ]]; then
            environment="Environment=\"MOCK_MODE=false\"\nEnvironment=\"PORT=$port\"\nEnvironment=\"SSO_ENABLED=$sso_enabled\"\nEnvironment=\"PATH=$slurm_bin_path:$slurm_sbin_path:/usr/local/bin:/usr/bin:/bin\"\nEnvironment=\"SLURM_BIN_DIR=$slurm_bin_path\"\nEnvironmentFile=-$work_dir/.env"
        elif [[ "$service_type" == "node" ]]; then
            environment="Environment=\"NODE_ENV=development\"\nEnvironment=\"PORT=$port\"\nEnvironment=\"PATH=$slurm_bin_path:$slurm_sbin_path:/usr/local/bin:/usr/bin:/bin\"\nEnvironmentFile=-$work_dir/.env"
        else
            environment="Environment=\"PORT=$port\"\nEnvironment=\"PATH=$slurm_bin_path:$slurm_sbin_path:/usr/local/bin:/usr/bin:/bin\""
        fi

        cat > "$service_file" << EOF
[Unit]
Description=$service_name - Web Service ($service_type) - Port $port
After=network.target redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=$service_user
Group=$service_group
WorkingDirectory=$work_dir

# Environment
$(echo -e "$environment")

# Start command
ExecStart=/bin/bash -c '$start_command'

# Restart policy
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=10

# Resource limits
MemoryLimit=2G
CPUQuota=200%

# Logging
StandardOutput=append:/var/log/web_services/$service_name.log
StandardError=append:/var/log/web_services/$service_name.error.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        log_success "Systemd service created: $service_name"
    else
        log_info "[DRY-RUN] Would create systemd service: $service_name"
    fi
}

# Function to generate Nginx upstream configuration
generate_nginx_upstreams() {
    log_info "Generating Nginx upstream configuration..."

    local upstreams=""

    # Generate upstream blocks for each service
    for controller in $WEB_CONTROLLERS; do
        local ip=$(echo "$controller" | cut -d: -f1)
        upstreams="${upstreams}    server ${ip}:5173;  # dashboard\n"
    done

    echo -e "$upstreams"
}

# Function to configure Nginx
configure_nginx() {
    log_info "Configuring Nginx reverse proxy (PRODUCTION MODE)..."

    if [[ "$DRY_RUN" == false ]]; then
        # Ensure WebSocket map directive exists in nginx.conf (required for $connection_upgrade variable)
        if ! grep -q 'connection_upgrade' /etc/nginx/nginx.conf 2>/dev/null; then
            log_info "Adding WebSocket map directive to nginx.conf..."

            # Add map directive after 'http {' line
            if grep -q 'http {' /etc/nginx/nginx.conf; then
                # Create backup
                cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup_$(date +%Y%m%d_%H%M%S)

                # Create a temp file with the map directive inserted
                awk '/http \{/{print; print "\n\t# WebSocket support (added by phase5_web.sh)"; print "\tmap $http_upgrade $connection_upgrade {"; print "\t\tdefault upgrade;"; print "\t\t\"\" close;"; print "\t}\n"; next}1' /etc/nginx/nginx.conf > /tmp/nginx.conf.new

                if [ -s /tmp/nginx.conf.new ]; then
                    mv /tmp/nginx.conf.new /etc/nginx/nginx.conf
                    log_success "WebSocket map directive added to nginx.conf"
                else
                    log_error "Failed to create modified nginx.conf"
                fi
            else
                log_warning "Could not find 'http {' in nginx.conf, WebSocket may not work"
            fi
        else
            log_info "WebSocket map directive already exists in nginx.conf"
        fi

        # Choose nginx configuration based on SSO setting
        if [[ "$SSO_ENABLED" == "false" ]]; then
            # SSO disabled: Use HTTP-only configuration (hpc-portal.conf)
            log_info "SSO disabled: Generating HTTP-only nginx configuration (hpc-portal.conf)..."
            local nginx_conf="/etc/nginx/conf.d/hpc-portal.conf"
            local nginx_template="$PROJECT_ROOT/dashboard/nginx/hpc-portal.conf"

            # Backup existing config if it exists
            if [[ -f "$nginx_conf" ]]; then
                cp "$nginx_conf" "${nginx_conf}.backup_$(date +%Y%m%d_%H%M%S)"
            fi

            # Check if source template exists
            if [[ -f "$nginx_template" ]]; then
                # Copy template and replace placeholders
                # server_name: use PUBLIC_URL from YAML (IP or hostname)
                # Path patterns: replace hardcoded paths with actual PROJECT_ROOT
                local server_hostname="${PUBLIC_URL:-localhost}"
                # Remove protocol prefix if present
                server_hostname="${server_hostname#http://}"
                server_hostname="${server_hostname#https://}"

                sed -e "s|/home/koopark/claude/KooSlurmInstallAutomationRefactory/|$PROJECT_ROOT/|g" \
                    -e "s|/home/[^/]\+/claude/[^/]\+/|$PROJECT_ROOT/|g" \
                    -e "s|server_name localhost;|server_name $server_hostname localhost;|g" \
                    -e "s|{{DOMAIN}}|$server_hostname|g" \
                    -e "s|{{PUBLIC_URL}}|$server_hostname|g" \
                    "$nginx_template" > "$nginx_conf"
                log_success "Generated $nginx_conf (server_name: $server_hostname localhost)"
            else
                log_warning "Nginx template not found: $nginx_template"
                # Fallback: Try to use generate_nginx_conf.sh
                local generate_script="$PROJECT_ROOT/dashboard/nginx/generate_nginx_conf.sh"
                if [[ -f "$generate_script" ]]; then
                    log_info "Attempting to generate nginx config using $generate_script..."
                    cd "$PROJECT_ROOT/dashboard/nginx"
                    bash generate_nginx_conf.sh
                    cd "$PROJECT_ROOT"

                    # Check if config was generated in sites-available, copy to conf.d (not symlink)
                    if [[ -f "/etc/nginx/sites-available/hpc-portal.conf" ]]; then
                        cp /etc/nginx/sites-available/hpc-portal.conf /etc/nginx/conf.d/hpc-portal.conf
                        log_success "Copied hpc-portal.conf to conf.d"
                    elif [[ -f "/etc/nginx/sites-available/hpc_web_services.conf" ]]; then
                        cp /etc/nginx/sites-available/hpc_web_services.conf /etc/nginx/conf.d/hpc-portal.conf
                        log_success "Copied hpc_web_services.conf to conf.d as hpc-portal.conf"
                    else
                        log_error "No nginx config was generated"
                        return 1
                    fi
                else
                    log_error "No nginx template or generate script found"
                    return 1
                fi
            fi

            # Disable auth-portal.conf if it exists (conflicts with hpc-portal.conf)
            if [[ -f "/etc/nginx/conf.d/auth-portal.conf" ]]; then
                log_info "Disabling auth-portal.conf (SSO disabled, using HTTP-only config)"
                mv /etc/nginx/conf.d/auth-portal.conf /etc/nginx/conf.d/auth-portal.conf.disabled_$(date +%Y%m%d_%H%M%S)
            fi
        else
            # SSO enabled: Use HTTPS configuration (auth-portal.conf)
            log_info "SSO enabled: Using HTTPS nginx configuration (auth-portal.conf)..."
            local nginx_conf="/etc/nginx/conf.d/auth-portal.conf"
            local nginx_template="$PROJECT_ROOT/dashboard/nginx/auth-portal.conf"

            # Backup existing config if it exists
            if [[ -f "$nginx_conf" ]]; then
                cp "$nginx_conf" "${nginx_conf}.backup_$(date +%Y%m%d_%H%M%S)"
            fi

            # Use template if available, otherwise try to update existing
            if [[ -f "$nginx_template" ]]; then
                # Copy template and replace placeholders
                # server_name: use PUBLIC_URL from YAML (IP or hostname)
                local server_hostname="${PUBLIC_URL:-localhost}"
                # Remove protocol prefix if present
                server_hostname="${server_hostname#http://}"
                server_hostname="${server_hostname#https://}"

                sed -e "s|/home/koopark/claude/KooSlurmInstallAutomationRefactory/|$PROJECT_ROOT/|g" \
                    -e "s|/home/[^/]\+/claude/[^/]\+/|$PROJECT_ROOT/|g" \
                    -e "s|server_name auth.hpc.local;|server_name $server_hostname localhost;|g" \
                    "$nginx_template" > "$nginx_conf"
                log_success "Generated $nginx_conf from template (HTTPS with SSO, server_name: $server_hostname)"
            elif [[ -f "$nginx_conf" ]]; then
                # Fallback: Update existing config
                sed -i -e "s|server_name [0-9.]\+ localhost|server_name $PUBLIC_URL localhost|g" \
                       -e "s|alias /home/[^/]\+/claude/KooSlurmInstallAutomationRefactory/|alias $PROJECT_ROOT/|g" \
                       "$nginx_conf"
                log_success "Updated $nginx_conf with PUBLIC_URL=$PUBLIC_URL (HTTPS with SSO)"
            else
                log_error "auth-portal.conf template not found: $nginx_template"
                return 1
            fi

            # Disable hpc-portal.conf if it exists (conflicts with auth-portal.conf)
            if [[ -f "/etc/nginx/conf.d/hpc-portal.conf" ]]; then
                log_info "Disabling hpc-portal.conf (SSO enabled, using HTTPS config)"
                mv /etc/nginx/conf.d/hpc-portal.conf /etc/nginx/conf.d/hpc-portal.conf.disabled_$(date +%Y%m%d_%H%M%S)
            fi
        fi

        # Ensure web_services symlink is disabled to avoid conflict
        if [[ -L "/etc/nginx/sites-enabled/web_services" ]]; then
            log_info "Removing conflicting web_services symlink"
            rm -f "/etc/nginx/sites-enabled/web_services"
        fi

        # Remove default site if it exists (conflicts with our config)
        if [[ -L "/etc/nginx/sites-enabled/default" ]]; then
            log_info "Removing default nginx site to avoid conflict"
            rm -f "/etc/nginx/sites-enabled/default"
        fi

        # Ensure nginx.conf includes conf.d directory
        if ! grep -q 'include /etc/nginx/conf.d/\*.conf' /etc/nginx/nginx.conf 2>/dev/null; then
            log_warning "nginx.conf does not include conf.d/*.conf, adding it..."

            # Backup nginx.conf
            cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup_conf_d_$(date +%Y%m%d_%H%M%S)

            # Add include directive before the closing brace of http block
            if grep -q 'include /etc/nginx/sites-enabled/' /etc/nginx/nginx.conf; then
                # Add after sites-enabled include
                sed -i '/include \/etc\/nginx\/sites-enabled\//a\    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
            else
                # Add before closing brace of http block (last } in file)
                sed -i '/^}$/i\    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
            fi
            log_success "Added 'include /etc/nginx/conf.d/*.conf;' to nginx.conf"
        else
            log_info "nginx.conf already includes conf.d/*.conf"
        fi

        # NOTE: We only use conf.d for nginx configs, NOT sites-enabled
        # This avoids duplicate upstream errors when both conf.d and sites-enabled include same config
        # If sites-available has configs, they should be copied to conf.d, not symlinked to sites-enabled
        log_info "Ensuring no duplicate configs in sites-enabled (using conf.d only)..."
        rm -f /etc/nginx/sites-enabled/hpc-portal.conf 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/hpc_web_services.conf 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/auth-portal.conf 2>/dev/null || true

        # Test Nginx configuration
        if nginx -t 2>&1; then
            log_success "Nginx configuration valid"
        else
            log_error "Nginx configuration test failed"
            nginx -t
            return 1
        fi

        # Set proper permissions for nginx to access static files
        log_info "Setting permissions for nginx to access frontend files..."

        # Ensure project directory is accessible (execute permission on directories)
        local project_dir="$PROJECT_ROOT"
        local current_dir="$project_dir"

        # Set execute permission on all parent directories up to /home
        while [[ "$current_dir" != "/" && "$current_dir" != "/home" ]]; do
            if [[ -d "$current_dir" ]]; then
                chmod o+x "$current_dir" 2>/dev/null || true
            fi
            current_dir=$(dirname "$current_dir")
        done
        chmod o+x /home 2>/dev/null || true

        # Set read permission on dashboard directory and subdirectories
        if [[ -d "$PROJECT_ROOT/dashboard" ]]; then
            # Make all directories accessible
            find "$PROJECT_ROOT/dashboard" -type d -exec chmod o+rx {} \; 2>/dev/null || true
            # Make all files readable
            find "$PROJECT_ROOT/dashboard" -type f -exec chmod o+r {} \; 2>/dev/null || true
            log_success "Frontend directories are now accessible by nginx"
        fi

        # Fix "Too many open files" issue by increasing nginx file descriptor limits
        log_info "Configuring Nginx systemd limits to prevent 'Too many open files' errors..."
        mkdir -p /etc/systemd/system/nginx.service.d/
        cat > /etc/systemd/system/nginx.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65536
EOF
        log_success "Nginx file descriptor limit set to 65536"

        # Reload systemd to apply changes
        systemctl daemon-reload
        log_info "Systemd configuration reloaded"

        # Reload nginx to apply new configuration
        log_info "Reloading nginx to apply configuration..."
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx || systemctl restart nginx
            log_success "Nginx reloaded with new configuration"
        else
            systemctl start nginx
            log_success "Nginx started with new configuration"
        fi
    else
        log_info "[DRY-RUN] Would check/create nginx configuration"
    fi

    log_success "Nginx configured for production"
}


# Function to fix SSH API and Nginx configuration
fix_ssh_api_and_nginx() {
    log_info "Fixing SSH API and Nginx configuration..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    if [[ "$DRY_RUN" == false ]]; then
        # 1. Fix ssh_api.py url_prefix
        local ssh_api="$dashboard_dir/backend_5010/ssh_api.py"
        if [[ -f "$ssh_api" ]]; then
            if grep -q "url_prefix='/ssh'" "$ssh_api"; then
                sed -i "s|url_prefix='/ssh'|url_prefix='/api/ssh'|g" "$ssh_api"
                log_success "Fixed ssh_api.py url_prefix to /api/ssh"
            else
                log_info "ssh_api.py url_prefix already correct"
            fi
        fi

        # 2. Fix SSHSessionManager.tsx API paths
        local ssh_manager="$dashboard_dir/frontend_3010/src/components/SSHSessionManager.tsx"
        if [[ -f "$ssh_manager" ]]; then
            if grep -q "API_CONFIG.API_BASE_URL}/ssh" "$ssh_manager"; then
                sed -i "s|API_CONFIG.API_BASE_URL}/ssh|API_CONFIG.API_BASE_URL}/api/ssh|g" "$ssh_manager"
                log_success "Fixed SSHSessionManager.tsx API paths to /api/ssh"
            else
                log_info "SSHSessionManager.tsx API paths already correct"
            fi
        fi

        # 3. Fix Nginx config dashboard path (based on SSO setting)
        local nginx_conf_file
        if [[ "$SSO_ENABLED" == "false" ]]; then
            nginx_conf_file="/etc/nginx/conf.d/hpc-portal.conf"
        else
            nginx_conf_file="/etc/nginx/conf.d/auth-portal.conf"
        fi

        if [[ -f "$nginx_conf_file" ]]; then
            if grep -q "alias /var/www/html/frontend_3010" "$nginx_conf_file"; then
                sed -i 's|alias /var/www/html/frontend_3010|alias /var/www/html/dashboard|g' "$nginx_conf_file"
                log_success "Fixed $(basename $nginx_conf_file) dashboard path"
            else
                log_info "$(basename $nginx_conf_file) dashboard path already correct"
            fi
        fi

        # 4. Fix Nginx hpc_web_services.conf if it exists
        if [[ -f "/etc/nginx/sites-available/hpc_web_services.conf" ]]; then
            if grep -q "alias /var/www/html/frontend_3010" /etc/nginx/sites-available/hpc_web_services.conf; then
                sed -i 's|alias /var/www/html/frontend_3010|alias /var/www/html/dashboard|g' /etc/nginx/sites-available/hpc_web_services.conf
                log_success "Fixed hpc_web_services.conf dashboard path"
            fi
        fi

        # 5. Remove old frontend_dashboard.service if exists
        if systemctl list-units --full --all | grep -q "frontend_dashboard.service"; then
            systemctl stop frontend_dashboard.service 2>/dev/null || true
            systemctl disable frontend_dashboard.service 2>/dev/null || true
            rm -f /etc/systemd/system/frontend_dashboard.service
            systemctl daemon-reload
            log_success "Removed old frontend_dashboard.service"
        fi


        # 6. Add SocketIO proxy to Nginx config (based on SSO setting)
        if [[ -f "$nginx_conf_file" ]]; then
            if ! grep -q "location /socket.io/" "$nginx_conf_file"; then
                # Find the line number after "location /ws" block
                local ws_end=$(grep -n "location /ws" "$nginx_conf_file" | head -1 | cut -d: -f1)
                ws_end=$((ws_end + 12))  # Skip to end of /ws block

                # Insert socket.io configuration
                sed -i "${ws_end}a\\
\\
    # SocketIO for SSH WebSocket (backend_5010)\\
    location /socket.io/ {\\
        proxy_pass http://localhost:5010/socket.io/;\\
        proxy_http_version 1.1;\\
        proxy_buffering off;\\
        proxy_set_header Upgrade \$http_upgrade;\\
        proxy_set_header Connection \"upgrade\";\\
        proxy_set_header Host \$host;\\
        proxy_set_header X-Real-IP \$remote_addr;\\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\\
        proxy_set_header X-Forwarded-Proto \$scheme;\\
        proxy_read_timeout 86400s;\\
        proxy_send_timeout 86400s;\\
    }" "$nginx_conf_file"

                log_success "Added SocketIO proxy to $(basename $nginx_conf_file)"
            else
                log_info "SocketIO proxy already exists in $(basename $nginx_conf_file)"
            fi
        fi
        log_success "SSH API and Nginx configuration fixed"
    else
        log_info "[DRY-RUN] Would fix SSH API and Nginx configuration"
    fi
}

# Function to setup SSL (supports letsencrypt, self_signed, or none)
setup_ssl() {
    if [[ "$SKIP_SSL" == true ]]; then
        log_warning "Skipping SSL setup (--skip-ssl flag)"
        return
    fi

    # Read SSL mode from YAML config (default: self_signed)
    local ssl_mode
    ssl_mode=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('mode', 'self_signed'))" 2>/dev/null || echo "self_signed")

    log_info "SSL mode from config: $ssl_mode"

    case "$ssl_mode" in
        none)
            log_warning "SSL disabled (mode: none). Using HTTP only."
            log_warning "⚠️  This is NOT recommended for production!"
            return
            ;;
        self_signed)
            log_info "Setting up self-signed SSL certificate..."
            setup_self_signed_ssl
            ;;
        letsencrypt)
            log_info "Setting up Let's Encrypt SSL certificate..."
            setup_letsencrypt_ssl
            ;;
        *)
            log_warning "Unknown SSL mode: $ssl_mode. Falling back to self_signed."
            setup_self_signed_ssl
            ;;
    esac

    log_success "SSL setup complete"
}

# Self-signed SSL certificate setup (for offline environments)
setup_self_signed_ssl() {
    if [[ "$DRY_RUN" == false ]]; then
        # Create SSL directories
        mkdir -p /etc/ssl/private
        chmod 700 /etc/ssl/private
        mkdir -p /etc/nginx/snippets

        # Generate self-signed certificate if not exists
        if [[ ! -f "/etc/ssl/certs/nginx-selfsigned.crt" ]]; then
            log_info "Generating self-signed SSL certificate (1 year validity)..."
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/ssl/private/nginx-selfsigned.key \
                -out /etc/ssl/certs/nginx-selfsigned.crt \
                -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=$DOMAIN" \
                2>/dev/null
            log_success "Self-signed certificate generated"
        else
            log_info "Self-signed certificate already exists"
        fi

        chmod 600 /etc/ssl/private/nginx-selfsigned.key
        chmod 644 /etc/ssl/certs/nginx-selfsigned.crt

        # Generate DH parameters if not exists (can take 1-5 minutes)
        if [[ ! -f "/etc/ssl/certs/dhparam.pem" ]]; then
            log_info "Generating DH parameters (this may take 1-5 minutes)..."
            openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 2>/dev/null
            chmod 644 /etc/ssl/certs/dhparam.pem
            log_success "DH parameters generated"
        fi

        # Create Nginx SSL snippets
        cat > /etc/nginx/snippets/self-signed.conf << 'EOF'
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF

        cat > /etc/nginx/snippets/ssl-params.conf << 'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
add_header Strict-Transport-Security "max-age=63072000" always;
# SAMEORIGIN: 같은 도메인 iframe 허용 (VNC/noVNC 가 대시보드 iframe 안에서 동작)
# DENY 면 VNC 콘솔이 'Refused to display in a frame' 로 안 뜸
add_header X-Frame-Options SAMEORIGIN always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

        log_success "Self-signed SSL configured"
    else
        log_info "[DRY-RUN] Would setup self-signed SSL certificate"
    fi
}

# Let's Encrypt SSL certificate setup (requires internet)
setup_letsencrypt_ssl() {
    # Get domain and email from YAML
    local ssl_domain ssl_email
    ssl_domain=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('domain', ''))" 2>/dev/null || echo "")
    ssl_email=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('email', ''))" 2>/dev/null || echo "")

    # Use cluster domain as fallback
    if [[ -z "$ssl_domain" ]]; then
        ssl_domain="$DOMAIN"
    fi
    if [[ -z "$ssl_email" ]]; then
        ssl_email="admin@$ssl_domain"
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Check if certificate already exists
        if [[ -d "/etc/letsencrypt/live/$ssl_domain" ]]; then
            log_info "Let's Encrypt certificate already exists for $ssl_domain"
        else
            # Stop Nginx temporarily
            systemctl stop nginx || true

            # Obtain certificate
            if certbot certonly --standalone \
                -d "$ssl_domain" \
                --non-interactive \
                --agree-tos \
                --email "$ssl_email" \
                --preferred-challenges http; then
                log_success "Let's Encrypt certificate obtained"
            else
                log_error "Failed to obtain Let's Encrypt certificate"
                log_warning "Falling back to self-signed certificate..."
                setup_self_signed_ssl
                return
            fi
        fi

        # Setup auto-renewal
        if ! crontab -l 2>/dev/null | grep -q certbot; then
            (crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
            log_success "SSL auto-renewal configured"
        fi
    else
        log_info "[DRY-RUN] Would setup Let's Encrypt certificate for $ssl_domain"
    fi
}

# Function to start web services
start_services() {
    log_info "Starting web services (PRODUCTION MODE: backends only)..."

    # =========================================================================
    # Redis 시작 및 비밀번호 설정 (다른 서비스보다 먼저)
    # =========================================================================
    log_info "Starting Redis with password from YAML..."
    if [[ "$DRY_RUN" == false ]]; then
        # Redis 설정 파일에 비밀번호 설정
        local redis_conf="/etc/redis/redis.conf"
        if [[ -f "$redis_conf" ]] && [[ -n "$REDIS_PASSWORD" ]]; then
            log_info "Configuring Redis password..."
            sed -i '/^requirepass /d' "$redis_conf" 2>/dev/null || true
            sed -i '/^# requirepass /d' "$redis_conf" 2>/dev/null || true
            echo "requirepass $REDIS_PASSWORD" >> "$redis_conf"
        fi

        # Redis 시작/재시작
        if systemctl is-active --quiet redis-server 2>/dev/null; then
            log_info "Restarting redis-server with new password..."
            systemctl restart redis-server
        elif systemctl is-active --quiet redis 2>/dev/null; then
            log_info "Restarting redis with new password..."
            systemctl restart redis
        else
            log_info "Starting redis-server..."
            systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null || true
            systemctl start redis-server 2>/dev/null || systemctl start redis 2>/dev/null || {
                # Fallback: 수동 시작
                if [[ -n "$REDIS_PASSWORD" ]]; then
                    redis-server --daemonize yes --requirepass "$REDIS_PASSWORD" 2>/dev/null
                else
                    redis-server --daemonize yes 2>/dev/null
                fi
            }
        fi
        sleep 2

        # Redis 연결 테스트
        if [[ -n "$REDIS_PASSWORD" ]]; then
            if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
                log_success "Redis started (authentication enabled)"
            else
                log_warning "Redis started but authentication failed"
            fi
        else
            if redis-cli ping 2>/dev/null | grep -q "PONG"; then
                log_success "Redis started (no authentication)"
            else
                log_warning "Redis ping failed"
            fi
        fi
    else
        log_info "[DRY-RUN] Would start and configure Redis"
    fi

    # Note: auth_frontend (auth_portal_4431) is built and served by Nginx as static files
    # No systemd service needed for frontend
    local services=(
        "auth_backend"
        "dashboard_backend"
        "websocket_service"
        "cae_backend"
        "cae_automation"
        "saml_idp"
        "prometheus"
        "node_exporter"
    )

    for service in "${services[@]}"; do
        if [[ "$DRY_RUN" == false ]]; then
            systemctl enable "$service" 2>/dev/null || true
            systemctl start "$service"

            if systemctl is-active --quiet "$service"; then
                log_success "$service started"
            else
                log_error "Failed to start $service"
            fi
        else
            log_info "[DRY-RUN] Would start $service"
        fi
    done

    # Reload and restart Nginx
    if [[ "$DRY_RUN" == false ]]; then
        systemctl enable nginx
        systemctl reload nginx || systemctl restart nginx
        if systemctl is-active --quiet nginx; then
            log_success "nginx reloaded"
        else
            log_error "Failed to reload nginx"
        fi
    fi

    log_success "All services started (PRODUCTION MODE)"
}

# Function to verify services
verify_services() {
    log_info "Verifying web services (PRODUCTION MODE)..."

    # Note: auth_frontend (auth_portal_4431) is served by Nginx as static files
    # Verify it via Nginx instead of systemd service
    local services=(
        "auth_backend:4430:/health:backend"
        "dashboard_backend:5010:/api/nodes:backend"
        "websocket_service:5011:/:backend"
        "cae_backend:5000:/:backend"
        "cae_automation:5001:/:backend"
    )

    local all_healthy=true

    # Check backend services
    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local port=$(echo "$service_info" | cut -d: -f2)
        local path=$(echo "$service_info" | cut -d: -f3)
        local service_type=$(echo "$service_info" | cut -d: -f4)

        if [[ "$DRY_RUN" == false ]]; then
            local is_healthy=false

            if [[ "$service_type" == "frontend" ]]; then
                # For frontend service (auth_frontend only in production)
                check_result=$(curl -sf -m 3 "http://localhost:$port$path" 2>&1)
                if [[ $? -eq 0 ]]; then
                    is_healthy=true
                    log_success "$service_name is healthy (dev mode)"
                fi
            else
                # For backend services - retry up to 15 times with 3s delay (45초 총 대기)
                local max_retries=15
                local retry_delay=3

                for ((retry=1; retry<=max_retries; retry++)); do
                    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://localhost:$port$path" 2>&1 || true)
                    if [[ "$http_code" =~ ^[2-5][0-9][0-9]$ ]]; then
                        is_healthy=true
                        if [[ $retry -gt 1 ]]; then
                            log_success "$service_name is healthy (HTTP $http_code) - ready after ${retry} attempts"
                        else
                            log_success "$service_name is healthy (HTTP $http_code)"
                        fi
                        break
                    fi

                    # If not last retry, wait and try again
                    if [[ $retry -lt $max_retries ]]; then
                        # 진행상황 표시 (5번째 시도마다)
                        if [[ $((retry % 5)) -eq 0 ]]; then
                            log_info "Still waiting for $service_name... (attempt $retry/$max_retries, HTTP: $http_code)"
                        fi
                        sleep $retry_delay
                    fi
                done
            fi

            if [[ "$is_healthy" == false ]]; then
                # Fallback: check if systemd service is running
                if systemctl is-active --quiet "$service_name.service" 2>/dev/null; then
                    is_healthy=true
                    log_warning "$service_name is starting (systemd running, HTTP not ready yet after ${max_retries} attempts)"
                else
                    log_error "$service_name is not responding (port $port) after ${max_retries} attempts"

                    # 실패한 서비스 진단 정보 수집
                    echo ""
                    log_error "=========================================="
                    log_error "Service Failure Diagnostic Information"
                    log_error "=========================================="
                    log_error "Service: $service_name"
                    log_error "Port: $port"
                    log_error "Health check endpoint: http://localhost:$port$path"
                    log_error "Last HTTP code: $http_code"
                    echo ""

                    # systemd 상태
                    log_error "--- systemd service status ---"
                    systemctl status "$service_name.service" --no-pager -l 2>&1 || true
                    echo ""

                    # 최근 로그 (stderr)
                    log_error "--- Recent error logs (last 30 lines) ---"
                    if [[ -f "/var/log/web_services/$service_name.error.log" ]]; then
                        tail -n 30 "/var/log/web_services/$service_name.error.log" 2>&1 || true
                    else
                        log_warning "Error log file not found: /var/log/web_services/$service_name.error.log"
                    fi
                    echo ""

                    # 최근 로그 (stdout)
                    log_error "--- Recent output logs (last 30 lines) ---"
                    if [[ -f "/var/log/web_services/$service_name.log" ]]; then
                        tail -n 30 "/var/log/web_services/$service_name.log" 2>&1 || true
                    else
                        log_warning "Output log file not found: /var/log/web_services/$service_name.log"
                    fi
                    echo ""

                    # 포트 사용 확인
                    log_error "--- Port usage check ---"
                    netstat -tlnp 2>/dev/null | grep ":$port " || echo "Port $port is not listening"
                    echo ""

                    # 프로세스 확인
                    log_error "--- Related processes ---"
                    ps aux | grep -E "$service_name|python.*$port|node.*$port" | grep -v grep || echo "No related processes found"
                    echo ""

                    log_error "=========================================="

                    all_healthy=false
                fi
            fi
        else
            log_info "[DRY-RUN] Would check $service_name at http://localhost:$port$path"
        fi
    done

    # Check Nginx and frontend paths
    if [[ "$DRY_RUN" == false ]]; then
        if systemctl is-active --quiet nginx; then
            log_success "nginx is running"

            # Test frontend paths through nginx
            local frontend_paths=(
                "/dashboard:Dashboard Frontend"
                "/vnc:VNC Frontend"
                "/app:App Frontend"
                "/koocae:KooCAEWeb Frontend"
            )

            for path_info in "${frontend_paths[@]}"; do
                local path=$(echo "$path_info" | cut -d: -f1)
                local name=$(echo "$path_info" | cut -d: -f2)

                http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://localhost$path" 2>&1)
                if [[ "$http_code" =~ ^[2-3][0-9][0-9]$ ]]; then
                    log_success "$name accessible via Nginx (HTTP $http_code)"
                else
                    log_warning "$name may not be built yet (HTTP $http_code)"
                fi
            done
        else
            log_error "nginx is not running"
            all_healthy=false
        fi
    fi

    echo ""
    echo "=========================================="
    echo "Health Check Summary"
    echo "=========================================="

    if [[ "$all_healthy" == true ]]; then
        log_success "✅ All services are healthy (PRODUCTION MODE)"
        echo ""
        return 0
    else
        echo ""
        log_error "❌ CRITICAL: Some services failed health check"
        log_error ""
        log_error "Next steps to debug:"
        log_error "  1. Check the diagnostic information printed above"
        log_error "  2. Review service logs: ls -lh /var/log/web_services/"
        log_error "  3. Check systemd status: systemctl status <service_name>"
        log_error "  4. Verify environment variables (especially SSO_ENABLED)"
        log_error "  5. Check if required dependencies are installed"
        log_error ""
        log_error "Common issues:"
        log_error "  - Missing Python/Node dependencies"
        log_error "  - Port conflicts (check: netstat -tlnp)"
        log_error "  - Permission errors (check log file ownership)"
        log_error "  - SSO_ENABLED environment variable not set correctly"
        log_error "  - YAML configuration file (my_multihead_cluster.yaml) not found"
        log_error ""
        log_error "Installation cannot proceed with unhealthy services."
        echo "=========================================="
        echo ""

        # 설치 중단
        exit 1
    fi
}

# Function to display summary
display_summary() {
    log_info "=== Web Services Setup Summary ==="
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Node: $CURRENT_NODE_IP"
    log_info "Domain: $DOMAIN"
    log_info ""
    log_info "Services deployed:"
    log_info "  - Dashboard: https://$DOMAIN/"
    log_info "  - Auth API: https://$DOMAIN/api/auth"
    log_info "  - Job API: https://$DOMAIN/api/jobs"
    log_info "  - WebSocket: wss://$DOMAIN/ws"
    log_info "  - File API: https://$DOMAIN/api/files"
    log_info "  - Monitoring: https://$DOMAIN/monitoring"
    log_info "  - Metrics API: https://$DOMAIN/api/monitoring"
    log_info "  - Admin Portal: https://$DOMAIN/admin"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Verify services: curl https://$DOMAIN/health"
    log_info "  2. Check logs: tail -f /var/log/web_services/*.log"
    log_info "  3. Access dashboard: https://$DOMAIN"
}

# Function to deploy VNC start scripts to viz nodes
deploy_vnc_scripts() {
    log_info "Deploying VNC start scripts to viz nodes..."

    # Get viz nodes from config using parser.py
    local viz_nodes=$(python3 "$SCRIPT_DIR/../config/parser.py" "$CONFIG_PATH" get-nodes --partition viz 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

    if [[ -z "$viz_nodes" ]]; then
        log_warning "No viz nodes found in config"
        return
    fi

    # Create the VNC start script content
    local script_content='#!/bin/bash
set -e

VNC_RESOLUTION=${VNC_RESOLUTION:-1280x720}
VNC_PORT=${VNC_PORT:-5901}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
DISPLAY_NUM=${1:-1}
export DISPLAY=:${DISPLAY_NUM}
export HOME=/root

echo "=== Starting GEdit (Fixed - No Background vncserver) ==="
echo "HOME=$HOME"
echo "DISPLAY=$DISPLAY"
echo "VNC_PORT=$VNC_PORT"
echo "WEBSOCKIFY_PORT=$WEBSOCKIFY_PORT"

# D-Bus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
fi

# VNC 정리
vncserver -kill $DISPLAY 2>/dev/null || true
rm -rf /tmp/.X${DISPLAY_NUM}-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X${DISPLAY_NUM} 2>/dev/null || true

# VNC 비밀번호 설정 - 중요!
echo "Setting up VNC password..."
mkdir -p ~/.vnc
echo "password" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
echo "Password file created: $(ls -lah ~/.vnc/passwd)"

# xstartup
cat > ~/.vnc/xstartup << '\''XSTARTUP'\''
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

xsetroot -solid grey &
xfwm4 &

(sleep 3 && DISPLAY=:1 gedit) &

while true; do sleep 3600; done
XSTARTUP
chmod +x ~/.vnc/xstartup

# VNC 시작 (NO BACKGROUND!)
echo "Starting VNC server (foreground)..."
vncserver $DISPLAY -geometry $VNC_RESOLUTION -depth 24 -localhost no

echo "VNC server started successfully"
sleep 3

# websockify (background is fine)
echo "Starting websockify..."
websockify --web /opt/novnc ${WEBSOCKIFY_PORT} localhost:${VNC_PORT} &

echo "✅ GEdit ready!"
echo "VNC: localhost:$VNC_PORT"
echo "WebSocket: ws://localhost:$WEBSOCKIFY_PORT"

# Keep script alive
while true; do sleep 3600; done
'

    # Deploy to each viz node
    for node in $viz_nodes; do
        # Get node IP and SSH user from YAML config
        local node_info
        node_info=$(python3 << EOFPY
import yaml
try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)
    # Search in compute_nodes (viz nodes are usually in compute_nodes)
    for n in config.get('nodes', {}).get('compute_nodes', []):
        if n.get('hostname') == '$node' or n.get('name') == '$node':
            ip = n.get('ip_address', n.get('ip', ''))
            user = n.get('ssh_user', 'root')
            print(f"{ip}|{user}")
            exit(0)
    # Also check controllers
    for n in config.get('nodes', {}).get('controllers', []):
        if n.get('hostname') == '$node' or n.get('name') == '$node':
            ip = n.get('ip_address', n.get('ip', ''))
            user = n.get('ssh_user', 'root')
            print(f"{ip}|{user}")
            exit(0)
except Exception as e:
    pass
EOFPY
)
        local node_ip=$(echo "$node_info" | cut -d'|' -f1)
        local ssh_user=$(echo "$node_info" | cut -d'|' -f2)

        # Fallback to yq if python parsing failed
        if [[ -z "$node_ip" ]]; then
            node_ip=$(yq eval ".nodes[] | select(.name == \"$node\") | .ip" "$CONFIG_PATH" 2>/dev/null)
            ssh_user="root"  # Default fallback
        fi

        if [[ -z "$node_ip" ]]; then
            log_warning "No IP found for node $node"
            continue
        fi

        log_info "Deploying VNC script to $node ($node_ip) as $ssh_user..."

        if [[ "$DRY_RUN" == false ]]; then
            setup_node_ssh_opts "$ssh_user" "$node_ip" || {
                log_warning "SSH auth failed for $node ($node_ip), skipping"
                continue
            }
            # Create /opt/scripts directory on viz node
            ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo mkdir -p /opt/scripts" || {
                log_warning "Failed to create /opt/scripts on $node"
                continue
            }

            # Deploy the script
            echo "$script_content" | ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo tee /opt/scripts/start-gedit-working.sh > /dev/null" || {
                log_warning "Failed to deploy script to $node"
                continue
            }

            # Make it executable
            ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo chmod +x /opt/scripts/start-gedit-working.sh" || {
                log_warning "Failed to set permissions on $node"
                continue
            }

            log_success "VNC script deployed to $node"
        else
            log_info "[DRY-RUN] Would deploy VNC script to $node ($node_ip) as $ssh_user"
        fi
    done

    log_success "VNC scripts deployment complete"
}

# Main function
main() {
    parse_args "$@"

    log_info "=== Phase 5: Web Services Setup (PRODUCTION MODE) ==="
    log_info "Starting at: $(date)"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN MODE: No changes will be made"
    fi

    check_root
    check_prerequisites
    preflight_port_check        # Report port conflicts before taking action
    stop_existing_services      # Stop nginx, redis, and backend services first
    stop_manual_web_services
    load_config
    create_web_user
    create_directories
    deploy_web_services
    build_all_frontends      # Build frontends for production
    deploy_vnc_scripts       # Deploy VNC start scripts to viz nodes
    create_systemd_services  # Only backends + auth_frontend
    configure_nginx          # Serve built frontends + proxy backends
    fix_ssh_api_and_nginx   # Fix SSH API paths and Nginx dashboard paths
    setup_ssl
    start_services
    verify_services

    # Apply post-setup fixes
    log_info "Applying post-setup fixes..."
    if [[ -f "$SCRIPT_DIR/apply_post_setup_fixes.sh" ]]; then
        # Export variables so apply_post_setup_fixes.sh can use them
        export REDIS_PASSWORD JWT_SECRET
        bash "$SCRIPT_DIR/apply_post_setup_fixes.sh" || log_warning "Post-setup fixes failed (non-critical)"
    else
        log_warning "Post-setup fixes script not found: $SCRIPT_DIR/apply_post_setup_fixes.sh"
    fi

    display_summary

    log_success "=== Phase 5 setup completed successfully (PRODUCTION MODE) ==="
    log_info "Finished at: $(date)"
}

# Run main function
main "$@"
