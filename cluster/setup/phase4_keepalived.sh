#!/bin/bash

#############################################################################
# Phase 4: Keepalived VIP Management Setup
#############################################################################
# Description:
#   Sets up Keepalived for Virtual IP (VIP) management with automatic failover
#   Integrates health checks for all services (Slurm, MariaDB, Redis, GlusterFS)
#
# Features:
#   - Dynamic keepalived.conf generation from template
#   - Priority-based VRRP configuration
#   - Service health check integration
#   - Notification scripts for state changes
#   - Integration with my_multihead_cluster.yaml
#
# Usage:
#   sudo ./cluster/setup/phase4_keepalived.sh [OPTIONS]
#
# Options:
#   --config PATH     Path to my_multihead_cluster.yaml
#   --dry-run         Show what would be done without executing
#   --help            Show this help message
#
# Author: Claude Code
# Date: 2025-10-27
#############################################################################

set -euo pipefail

#############################################################################
# Configuration
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# OS 감지 기반 오프라인 패키지 디렉토리 설정
source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
detect_os_version
set_offline_pkg_dir "$PROJECT_ROOT"

CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
PARSER_SCRIPT="${PROJECT_ROOT}/cluster/config/parser.py"
KEEPALIVED_TEMPLATE="${PROJECT_ROOT}/cluster/config/keepalived_template.conf"
KEEPALIVED_CONFIG="/etc/keepalived/keepalived.conf"
HEALTH_CHECK_SCRIPT="/usr/local/bin/keepalived_health_check.sh"
NOTIFY_MASTER_SCRIPT="/usr/local/bin/keepalived_notify_master.sh"
NOTIFY_BACKUP_SCRIPT="/usr/local/bin/keepalived_notify_backup.sh"
NOTIFY_FAULT_SCRIPT="/usr/local/bin/keepalived_notify_fault.sh"
LOG_FILE="/var/log/cluster_keepalived_setup.log"

# Default values
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################################################################
# Functions
#############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Color based on level
    local color=$NC
    case $level in
        ERROR) color=$RED ;;
        SUCCESS) color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        INFO) color=$BLUE ;;
    esac

    # Log to file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    # Log to console with color
    echo -e "${color}[$level]${NC} $message"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --config PATH     Path to my_multihead_cluster.yaml (default: $CONFIG_FILE)
  --dry-run         Show what would be done without executing
  --help            Show this help message

Examples:
  # Setup Keepalived with auto-detection
  sudo $0 --config ../my_multihead_cluster.yaml

  # Dry-run to preview changes
  $0 --dry-run
EOF
}

run_command() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local deps=("python3" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log ERROR "Required dependency not found: $dep"
            exit 1
        fi
    done

    # Check if keepalived template exists
    if [[ ! -f "$KEEPALIVED_TEMPLATE" ]]; then
        log ERROR "Keepalived template not found: $KEEPALIVED_TEMPLATE"
        exit 1
    fi

    log SUCCESS "All dependencies satisfied"
}

load_config() {
    log INFO "Loading configuration from $CONFIG_FILE..."

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERROR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    # Get current controller info
    CURRENT_CONTROLLER=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --current 2>/dev/null)
    if [[ -z "$CURRENT_CONTROLLER" ]]; then
        log ERROR "Could not detect current controller. Make sure this server's IP is in the config."
        exit 1
    fi

    # Extract current node info
    CURRENT_IP=$(echo "$CURRENT_CONTROLLER" | jq -r '.ip_address')
    CURRENT_HOSTNAME=$(echo "$CURRENT_CONTROLLER" | jq -r '.hostname')
    CURRENT_PRIORITY=$(echo "$CURRENT_CONTROLLER" | jq -r '.priority // 100')
    IS_VIP_OWNER=$(echo "$CURRENT_CONTROLLER" | jq -r '.vip_owner // false')

    # Check if Keepalived service is enabled
    KEEPALIVED_ENABLED=$(echo "$CURRENT_CONTROLLER" | jq -r '.services.keepalived // false')
    if [[ "$KEEPALIVED_ENABLED" != "true" ]]; then
        log ERROR "Keepalived service is not enabled for this controller in the config"
        exit 1
    fi

    log INFO "Current controller: $CURRENT_HOSTNAME ($CURRENT_IP)"
    log INFO "Priority: $CURRENT_PRIORITY"
    log INFO "VIP owner: $IS_VIP_OWNER"

    # Get VIP configuration using --get-vip option
    VIP_CONFIG=$(python3 "$PARSER_SCRIPT" --config "$CONFIG_FILE" --get-vip 2>/dev/null || echo "{}")

    VIP_ADDRESS=$(echo "$VIP_CONFIG" | jq -r '.address // empty' 2>/dev/null || echo "")
    VIP_NETMASK=$(echo "$VIP_CONFIG" | jq -r '.netmask // 24' 2>/dev/null || echo "24")
    VIP_INTERFACE=$(echo "$VIP_CONFIG" | jq -r '.interface // empty' 2>/dev/null || echo "")

    if [[ -z "$VIP_ADDRESS" ]]; then
        log ERROR "VIP address not configured in YAML"
        exit 1
    fi

    # 운영팀 정책: VIP 인터페이스는 YAML에 명시된 것만 사용
    # 자동 변경 시 bond0(운영망) 같은 잘못된 인터페이스가 선택되어
    # 라우팅 정책 위반 사고 발생함 (10.228.0.0/16 dev bond0 사례)
    if [[ -z "$VIP_INTERFACE" ]]; then
        log ERROR "VIP interface가 YAML에 명시되지 않았습니다."
        log ERROR "운영망 라우팅 사고 방지를 위해 자동 감지를 중단합니다."
        log ERROR "→ YAML의 high_availability.vip.interface 에 명시적 지정 필요"
        log ERROR "Available interfaces: $(ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')"
        exit 1
    fi

    if ! ip link show "$VIP_INTERFACE" &>/dev/null; then
        log ERROR "YAML 명시된 인터페이스 '$VIP_INTERFACE'가 이 노드에 없습니다."
        log ERROR "운영팀과 협의 후 YAML 수정 필요 (자동 fallback 금지)."
        log ERROR "Available interfaces: $(ip -o link show | awk -F': ' '{print $2}' | tr '\n' ' ')"
        exit 1
    fi

    # 운영팀 정책: bond/본딩 인터페이스에는 VIP 부여 금지
    # bond는 운영망(서비스망/컴퓨트망)에 연결되어 있어 VIP가 라우팅 충돌 유발
    if [[ "$VIP_INTERFACE" =~ ^bond[0-9]+$ ]]; then
        log ERROR "본딩 인터페이스($VIP_INTERFACE)에 VIP를 부여할 수 없습니다."
        log ERROR "운영팀 라우팅 정책 위반 — 별도 가상 인터페이스(ens*, eth*) 사용 필요"
        exit 1
    fi

    # netmask가 너무 크면(<=16) 운영망과 충돌할 수 있음
    if [[ "$VIP_NETMASK" -le 16 ]]; then
        log WARNING "VIP netmask /$VIP_NETMASK 가 너무 큼 — 운영망과 라우팅 충돌 가능"
        log WARNING "운영팀과 협의 후 적절한 서브넷(/24 권장)으로 좁힐 것"
    fi

    # Get authentication password
    AUTH_PASS=$(echo "$VIP_CONFIG" | jq -r '.auth_password // "default_pass"' 2>/dev/null || echo "default_pass")

    log INFO "VIP: $VIP_ADDRESS/$VIP_NETMASK on $VIP_INTERFACE"

    # Get enabled services for health check
    SERVICES=$(echo "$CURRENT_CONTROLLER" | jq -r '.services')
    HAS_GLUSTERFS=$(echo "$SERVICES" | jq -r '.glusterfs // false')
    HAS_MARIADB=$(echo "$SERVICES" | jq -r '.mariadb // false')
    HAS_REDIS=$(echo "$SERVICES" | jq -r '.redis // false')
    HAS_SLURM=$(echo "$SERVICES" | jq -r '.slurm // false')

    log SUCCESS "Configuration loaded successfully"
}

detect_os() {
    log INFO "Detecting operating system..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log INFO "Detected OS: $OS $OS_VERSION"
    else
        log ERROR "Cannot detect operating system"
        exit 1
    fi
}

check_keepalived_installed() {
    log INFO "Checking if Keepalived is installed..."

    if command -v keepalived &> /dev/null; then
        log SUCCESS "Keepalived is already installed"
        KEEPALIVED_INSTALLED=true

        # Check version
        KEEPALIVED_VERSION=$(keepalived --version 2>&1 | head -1 | grep -oP '(?<=v)[\d.]+' || echo "unknown")
        log INFO "Keepalived version: $KEEPALIVED_VERSION"
    else
        log WARNING "Keepalived is not installed"
        KEEPALIVED_INSTALLED=false
    fi
}

install_keepalived() {
    if [[ "$KEEPALIVED_INSTALLED" == "true" ]]; then
        log INFO "Skipping Keepalived installation (already installed)"
        return 0
    fi

    log INFO "Installing Keepalived..."

    # Check for offline packages first
    local offline_pkgs="${OFFLINE_PKG_DIR}/apt_packages"
    local keepalived_deb="$offline_pkgs/keepalived_*.deb"

    if [[ -d "$offline_pkgs" ]] && compgen -G "$keepalived_deb" > /dev/null 2>&1; then
        log INFO "Found offline packages, installing via local APT repository..."

        if [[ "$DRY_RUN" == "false" ]]; then
            # Setup local APT repository for safe installation
            local repo_list="/etc/apt/sources.list.d/offline-keepalived.list"

            # Ensure Packages.gz exists for APT
            if [[ ! -f "$offline_pkgs/Packages.gz" ]]; then
                log INFO "Creating APT repository index..."
                (cd "$offline_pkgs" && dpkg-scanpackages . /dev/null > Packages && gzip -k -f Packages) 2>/dev/null || true
            fi

            # Configure local APT repository
            echo "deb [trusted=yes] file://$offline_pkgs ./" | sudo tee "$repo_list" > /dev/null

            # Update APT cache with local repository only
            sudo apt-get update -o Dir::Etc::sourcelist="$repo_list" \
                                -o Dir::Etc::sourceparts="-" \
                                -o APT::Get::List-Cleanup="0" 2>/dev/null || true

            # Install Keepalived via APT (handles dependencies automatically)
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                keepalived 2>/dev/null || {
                log WARNING "APT install failed, trying with -f flag..."
                sudo apt-get install -f -y 2>/dev/null || true
            }

            # Cleanup: remove temporary repository config
            sudo rm -f "$repo_list" 2>/dev/null || true

            log SUCCESS "Keepalived installed from offline packages via APT"
        else
            log INFO "[DRY-RUN] Would install Keepalived from offline packages via APT"
        fi
    else
        # Online installation fallback
        log INFO "No offline packages found, installing online..."

        case $OS in
            ubuntu|debian)
                run_command "apt-get update"
                run_command "DEBIAN_FRONTEND=noninteractive apt-get install -y keepalived"
                ;;
            centos|rhel|rocky|almalinux)
                run_command "yum install -y keepalived"
                ;;
        esac

        log SUCCESS "Keepalived installed successfully (online)"
    fi
}

create_health_check_script() {
    log INFO "Creating health check script..."

    local script_content='#!/bin/bash
#
# Keepalived Health Check Script
# Checks if critical services are running
# Exit 0 = healthy, Exit 1 = unhealthy
#

# Services to check (from YAML configuration)
CHECK_GLUSTERFS={{CHECK_GLUSTERFS}}
CHECK_MARIADB={{CHECK_MARIADB}}
CHECK_REDIS={{CHECK_REDIS}}
CHECK_SLURM={{CHECK_SLURM}}

# Exit code (0 = all healthy)
EXIT_CODE=0

# TCP port check helper (timeout 2s)
check_port() {
    timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$1" 2>/dev/null
}

# Check GlusterFS
if [[ "$CHECK_GLUSTERFS" == "true" ]]; then
    if ! systemctl is-active --quiet glusterd; then
        echo "GlusterFS is not running"
        EXIT_CODE=1
    elif ! check_port 24007; then
        echo "GlusterFS port 24007 not responding"
        EXIT_CODE=1
    fi
fi

# Check MariaDB
if [[ "$CHECK_MARIADB" == "true" ]]; then
    if ! systemctl is-active --quiet mariadb; then
        echo "MariaDB is not running"
        EXIT_CODE=1
    elif ! check_port 3306; then
        echo "MariaDB port 3306 not responding"
        EXIT_CODE=1
    fi
fi

# Check Redis
if [[ "$CHECK_REDIS" == "true" ]]; then
    if ! systemctl is-active --quiet redis-server && ! systemctl is-active --quiet redis; then
        echo "Redis is not running"
        EXIT_CODE=1
    elif ! check_port 6379; then
        echo "Redis port 6379 not responding"
        EXIT_CODE=1
    fi
fi

# Check Slurm
if [[ "$CHECK_SLURM" == "true" ]]; then
    if ! systemctl is-active --quiet slurmctld; then
        echo "Slurm controller is not running"
        EXIT_CODE=1
    elif ! check_port 6817; then
        echo "Slurmctld port 6817 not responding"
        EXIT_CODE=1
    fi
fi

exit $EXIT_CODE
'

    # Substitute service checks
    script_content="${script_content//\{\{CHECK_GLUSTERFS\}\}/$HAS_GLUSTERFS}"
    script_content="${script_content//\{\{CHECK_MARIADB\}\}/$HAS_MARIADB}"
    script_content="${script_content//\{\{CHECK_REDIS\}\}/$HAS_REDIS}"
    script_content="${script_content//\{\{CHECK_SLURM\}\}/$HAS_SLURM}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create health check script at: $HEALTH_CHECK_SCRIPT"
    else
        echo "$script_content" > "$HEALTH_CHECK_SCRIPT"
        chmod +x "$HEALTH_CHECK_SCRIPT"
        log SUCCESS "Health check script created: $HEALTH_CHECK_SCRIPT"
    fi
}

create_notify_scripts() {
    log INFO "Creating notification scripts..."

    # Master script
    local notify_master='#!/bin/bash
#
# Keepalived Notify Master Script
# Called when this node becomes MASTER (VIP owner)
#

TYPE=$1
NAME=$2
STATE=$3

LOGFILE="/var/log/keepalived_notify.log"

echo "$(date): Transitioned to MASTER state" >> "$LOGFILE"
echo "  Type: $TYPE" >> "$LOGFILE"
echo "  Name: $NAME" >> "$LOGFILE"
echo "  State: $STATE" >> "$LOGFILE"

# Optional: Send email notification
# echo "Keepalived on $(hostname) became MASTER" | mail -s "Keepalived Alert" admin@example.com

# Optional: Restart services that depend on VIP
# systemctl restart slurmctld
'

    # Backup script
    local notify_backup='#!/bin/bash
#
# Keepalived Notify Backup Script
# Called when this node becomes BACKUP
#

TYPE=$1
NAME=$2
STATE=$3

LOGFILE="/var/log/keepalived_notify.log"

echo "$(date): Transitioned to BACKUP state" >> "$LOGFILE"
echo "  Type: $TYPE" >> "$LOGFILE"
echo "  Name: $NAME" >> "$LOGFILE"
echo "  State: $STATE" >> "$LOGFILE"
'

    # Fault script
    local notify_fault='#!/bin/bash
#
# Keepalived Notify Fault Script
# Called when health check fails
#

TYPE=$1
NAME=$2
STATE=$3

LOGFILE="/var/log/keepalived_notify.log"

echo "$(date): Transitioned to FAULT state" >> "$LOGFILE"
echo "  Type: $TYPE" >> "$LOGFILE"
echo "  Name: $NAME" >> "$LOGFILE"
echo "  State: $STATE" >> "$LOGFILE"

# Optional: Send alert
# echo "Keepalived on $(hostname) is in FAULT state" | mail -s "Keepalived ALERT" admin@example.com
'

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create notification scripts"
    else
        echo "$notify_master" > "$NOTIFY_MASTER_SCRIPT"
        echo "$notify_backup" > "$NOTIFY_BACKUP_SCRIPT"
        echo "$notify_fault" > "$NOTIFY_FAULT_SCRIPT"

        chmod +x "$NOTIFY_MASTER_SCRIPT"
        chmod +x "$NOTIFY_BACKUP_SCRIPT"
        chmod +x "$NOTIFY_FAULT_SCRIPT"

        log SUCCESS "Notification scripts created"
    fi
}

generate_keepalived_config() {
    log INFO "Generating Keepalived configuration from template..."

    # Debug: Show current interface value
    log INFO "DEBUG: VIP_INTERFACE='$VIP_INTERFACE'"

    # Sanity check
    if [[ -z "$VIP_INTERFACE" ]] || [[ "$VIP_INTERFACE" == "lo" ]]; then
        log ERROR "Invalid interface '$VIP_INTERFACE' in generate_keepalived_config"
        exit 1
    fi

    # Determine state (MASTER or BACKUP)
    if [[ "$IS_VIP_OWNER" == "true" ]]; then
        STATE="MASTER"
    else
        STATE="BACKUP"
    fi

    # Preemption configuration
    if [[ "$IS_VIP_OWNER" == "true" ]]; then
        # VIP owner should preempt (take back VIP when it recovers)
        PREEMPT_CONFIG=""
        PREEMPT_DELAY_CONFIG="garp_master_delay 5"
    else
        # Backups should not preempt
        PREEMPT_CONFIG="nopreempt"
        PREEMPT_DELAY_CONFIG=""
    fi

    # Read template and substitute variables
    local config_content
    config_content=$(cat "$KEEPALIVED_TEMPLATE")

    # Substitute template variables
    config_content="${config_content//\{\{HOSTNAME\}\}/$CURRENT_HOSTNAME}"
    config_content="${config_content//\{\{STATE\}\}/$STATE}"
    config_content="${config_content//\{\{INTERFACE\}\}/$VIP_INTERFACE}"
    config_content="${config_content//\{\{PRIORITY\}\}/$CURRENT_PRIORITY}"
    config_content="${config_content//\{\{AUTH_PASS\}\}/$AUTH_PASS}"
    config_content="${config_content//\{\{VIP_ADDRESS\}\}/$VIP_ADDRESS}"
    config_content="${config_content//\{\{VIP_NETMASK\}\}/$VIP_NETMASK}"
    config_content="${config_content//\{\{HEALTH_CHECK_SCRIPT\}\}/$HEALTH_CHECK_SCRIPT}"
    config_content="${config_content//\{\{NOTIFY_MASTER_SCRIPT\}\}/$NOTIFY_MASTER_SCRIPT}"
    config_content="${config_content//\{\{NOTIFY_BACKUP_SCRIPT\}\}/$NOTIFY_BACKUP_SCRIPT}"
    config_content="${config_content//\{\{NOTIFY_FAULT_SCRIPT\}\}/$NOTIFY_FAULT_SCRIPT}"
    config_content="${config_content//\{\{PREEMPT_CONFIG\}\}/$PREEMPT_CONFIG}"
    config_content="${config_content//\{\{PREEMPT_DELAY_CONFIG\}\}/$PREEMPT_DELAY_CONFIG}"

    # Backup existing config
    if [[ -f "$KEEPALIVED_CONFIG" ]] && [[ "$DRY_RUN" == "false" ]]; then
        cp "$KEEPALIVED_CONFIG" "${KEEPALIVED_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        log INFO "Backed up existing config"
    fi

    # Write configuration file
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would write Keepalived config to: $KEEPALIVED_CONFIG"
        log INFO "[DRY-RUN] Config preview (first 40 lines):"
        echo "$config_content" | head -40
    else
        mkdir -p "$(dirname "$KEEPALIVED_CONFIG")"
        echo "$config_content" > "$KEEPALIVED_CONFIG"
        chmod 644 "$KEEPALIVED_CONFIG"
        log SUCCESS "Keepalived configuration written to $KEEPALIVED_CONFIG"
    fi
}

enable_ip_forwarding() {
    log INFO "Enabling IP forwarding and non-local bind..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Enable IP forwarding
        sysctl -w net.ipv4.ip_forward=1 &>/dev/null || true

        # Enable non-local bind (allow binding to VIP before it's assigned)
        sysctl -w net.ipv4.ip_nonlocal_bind=1 &>/dev/null || true

        # Make persistent
        if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
            echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        fi
        if ! grep -q "net.ipv4.ip_nonlocal_bind" /etc/sysctl.conf; then
            echo "net.ipv4.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
        fi

        log SUCCESS "IP forwarding and non-local bind enabled"
    else
        log INFO "[DRY-RUN] Would enable IP forwarding and non-local bind"
    fi
}

start_keepalived() {
    log INFO "Starting Keepalived service..."

    # Enable service
    run_command "systemctl enable keepalived"

    # Start service
    run_command "systemctl restart keepalived"

    # Wait for service to start
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 3

        if systemctl is-active --quiet keepalived; then
            log SUCCESS "Keepalived started successfully"
        else
            log ERROR "Failed to start Keepalived"
            log ERROR "Status: $(systemctl is-active keepalived 2>&1 || echo 'inactive')"
            log ERROR "Recent logs:"
            journalctl -u keepalived -n 10 --no-pager 2>&1 | while read -r line; do
                log ERROR "  $line"
            done
            exit 1
        fi
    fi
}

show_vip_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log INFO "VIP status:"

    # Check if VIP is assigned to this node
    if ip addr show "$VIP_INTERFACE" | grep -q "$VIP_ADDRESS"; then
        log SUCCESS "VIP $VIP_ADDRESS is assigned to this node (MASTER)"
    else
        log INFO "VIP $VIP_ADDRESS is not assigned to this node (BACKUP)"
    fi

    echo ""
    log INFO "Full interface status:"
    ip addr show "$VIP_INTERFACE" | grep inet || true
}

#############################################################################
# Main
#############################################################################

main() {
    log INFO "=== Phase 4: Keepalived VIP Management Setup ==="
    log INFO "Starting at $(date)"

    # Step 0: Check root privileges
    log INFO "[Step 0/11] Checking root privileges..."
    check_root
    log SUCCESS "[Step 0/11] Root privileges OK"

    # Step 1: Check dependencies
    log INFO "[Step 1/11] Checking dependencies..."
    check_dependencies
    log SUCCESS "[Step 1/11] Dependencies OK"

    # Step 2: Load configuration
    log INFO "[Step 2/11] Loading configuration..."
    load_config
    log SUCCESS "[Step 2/11] Configuration loaded"

    # Step 3: Detect OS
    log INFO "[Step 3/11] Detecting OS..."
    detect_os
    log SUCCESS "[Step 3/11] OS detected"

    # Step 4: Check if Keepalived is installed
    log INFO "[Step 4/11] Checking Keepalived installation..."
    check_keepalived_installed
    log SUCCESS "[Step 4/11] Keepalived check done"

    # Step 5: Install Keepalived if needed
    log INFO "[Step 5/11] Installing Keepalived if needed..."
    if [[ "$KEEPALIVED_INSTALLED" == "false" ]]; then
        install_keepalived
    fi
    log SUCCESS "[Step 5/11] Keepalived installation done"

    # Step 6: Create health check script
    log INFO "[Step 6/11] Creating health check script..."
    create_health_check_script
    log SUCCESS "[Step 6/11] Health check script created"

    # Step 7: Create notification scripts
    log INFO "[Step 7/11] Creating notification scripts..."
    create_notify_scripts
    log SUCCESS "[Step 7/11] Notification scripts created"

    # Step 8: Generate Keepalived configuration
    log INFO "[Step 8/11] Generating Keepalived configuration..."
    generate_keepalived_config
    log SUCCESS "[Step 8/11] Keepalived configuration generated"

    # Step 9: Enable IP forwarding
    log INFO "[Step 9/11] Enabling IP forwarding..."
    enable_ip_forwarding
    log SUCCESS "[Step 9/11] IP forwarding enabled"

    # Step 10: Start Keepalived
    log INFO "[Step 10/11] Starting Keepalived service..."
    start_keepalived
    log SUCCESS "[Step 10/11] Keepalived service started"

    # Step 11: Show VIP status
    log INFO "[Step 11/11] Showing VIP status..."
    show_vip_status
    log SUCCESS "[Step 11/11] VIP status displayed"

    log SUCCESS "=== Phase 4: Keepalived setup completed successfully ==="
    log INFO "Finished at $(date)"

    log INFO ""
    log INFO "Next steps:"
    log INFO "  1. Run this script on all other Keepalived-enabled controllers"
    log INFO "  2. Check VIP status: ip addr show $VIP_INTERFACE | grep $VIP_ADDRESS"
    log INFO "  3. Test failover: sudo systemctl stop keepalived (on MASTER)"
    log INFO "  4. Monitor logs: tail -f /var/log/keepalived_notify.log"
    log INFO "  5. Check Keepalived status: sudo systemctl status keepalived"
}

#############################################################################
# Parse arguments
#############################################################################

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
        --help)
            show_help
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main
