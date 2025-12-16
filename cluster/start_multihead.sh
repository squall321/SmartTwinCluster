#!/bin/bash

################################################################################
# Main Multi-Head Cluster Orchestration Script
#
# This script orchestrates the complete setup of a multi-head HPC cluster
# by executing all phases in the correct order with dependency management.
#
# Phases:
#   Phase 0: Basic Infrastructure (config parser, auto-discovery)
#   Phase 1: GlusterFS (distributed storage)
#   Phase 2: MariaDB Galera (database cluster)
#   Phase 3: Redis Cluster (cache and sessions)
#   Phase 4: Slurm Multi-Master (job scheduler)
#   Phase 5: Keepalived (VIP management)
#   Phase 6: Web Services (user interfaces and APIs)
#   Phase 7: Backup System (unified backup/restore)
#   Phase 8: Container Images (deploy .sif files to nodes)
#
# Usage:
#   sudo ./start_multihead.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
#   --phase PHASE       Run specific phase only (0-7, or phase name)
#   --skip-phase PHASE  Skip specific phase
#   --dry-run           Preview actions without executing
#   --force             Force setup even if already configured
#   --skip-ssl          Skip SSL certificate generation (for web services)
#   --auto-confirm      Skip confirmation prompts
#   --help              Show this help message
#
# Examples:
#   sudo ./start_multihead.sh --config ../my_multihead_cluster.yaml
#   sudo ./start_multihead.sh --phase 1 --dry-run
#   sudo ./start_multihead.sh --skip-phase 6 --skip-phase 7
#   sudo ./start_multihead.sh --phase storage
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
SPECIFIC_PHASE=""
SKIP_PHASES=()
DRY_RUN=false
FORCE=false
SKIP_SSL=false
AUTO_CONFIRM=false
LOG_FILE="/var/log/cluster_multihead_setup.log"

# Phase mapping
declare -A PHASE_NAMES=(
    ["0"]="infrastructure"
    ["1"]="storage"
    ["2"]="database"
    ["3"]="redis"
    ["4"]="slurm"
    ["5"]="keepalived"
    ["6"]="web"
    ["7"]="backup"
    ["8"]="containers"
)

declare -A PHASE_NUMBERS=(
    ["infrastructure"]="0"
    ["storage"]="1"
    ["database"]="2"
    ["redis"]="3"
    ["slurm"]="4"
    ["keepalived"]="5"
    ["web"]="6"
    ["backup"]="7"
    ["containers"]="8"
)

declare -A PHASE_SCRIPTS=(
    ["0"]="N/A"  # Phase 0 has no setup script, just validation
    ["1"]="setup/phase0_storage.sh"
    ["2"]="setup/phase1_database.sh"
    ["3"]="setup/phase2_redis.sh"
    ["4"]="setup/phase3_slurm.sh"
    ["5"]="setup/phase4_keepalived.sh"
    ["6"]="setup/phase5_web.sh"
    ["7"]="N/A"  # Phase 7 is backup system, no setup needed
    ["8"]="setup/phase8_containers.sh"
)

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

log_phase() {
    echo -e "${CYAN}[PHASE $1]${NC} $2" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${CYAN}[PHASE $1]${NC} $2"
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
            --phase)
                SPECIFIC_PHASE="$2"
                shift 2
                ;;
            --skip-phase)
                SKIP_PHASES+=("$2")
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
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
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Initialize log file with proper permissions
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/cluster_multihead_setup.log"
    chmod 644 "$LOG_FILE" 2>/dev/null || true
}

# Function to normalize phase identifier (name or number -> number)
normalize_phase() {
    local phase=$1

    # If it's already a number, return it
    if [[ "$phase" =~ ^[0-8]$ ]]; then
        echo "$phase"
        return 0
    fi

    # If it's a name, convert to number
    if [[ -n "${PHASE_NUMBERS[$phase]:-}" ]]; then
        echo "${PHASE_NUMBERS[$phase]}"
        return 0
    fi

    log_error "Unknown phase: $phase"
    log_info "Valid phases: 0-8 or ${!PHASE_NUMBERS[*]}"
    return 1
}

# Function to check if phase should be skipped
should_skip_phase() {
    local phase=$1

    # Check if SKIP_PHASES array is empty
    if [[ ${#SKIP_PHASES[@]} -eq 0 ]]; then
        return 1
    fi

    for skip_phase in "${SKIP_PHASES[@]}"; do
        local normalized_skip
        normalized_skip=$(normalize_phase "$skip_phase")
        if [[ "$normalized_skip" == "$phase" ]]; then
            return 0
        fi
    done

    return 1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check config file
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi

    # Check parser.py
    if [[ ! -f "$SCRIPT_DIR/config/parser.py" ]]; then
        log_error "Parser script not found: $SCRIPT_DIR/config/parser.py"
        exit 1
    fi

    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi

    # Validate YAML configuration
    log_info "Validating configuration..."
    if ! python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" validate &>/dev/null; then
        log_error "Configuration validation failed"
        python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" validate
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to display cluster information
display_cluster_info() {
    log_info "=== Cluster Configuration ==="

    local cluster_name
    cluster_name=$(python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-value cluster_info.cluster_name 2>/dev/null || echo "unknown")
    log_info "Cluster Name: $cluster_name"

    # Get current node info - match against configured controllers
    local current_ip=""
    local all_ips=""
    all_ips=$(hostname -I)

    # Try to find IP that matches a controller in the config
    for ip in $all_ips; do
        if python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-controllers 2>/dev/null | jq -e ".[] | select(.ip_address == \"$ip\")" >/dev/null 2>&1; then
            current_ip="$ip"
            break
        fi
    done

    # Fallback to first IP if no match found
    if [[ -z "$current_ip" ]]; then
        current_ip=$(echo "$all_ips" | awk '{print $1}')
        log_warning "Current node IP not in controller list, using: $current_ip"
    fi

    log_info "Current Node: $current_ip"

    # Get controllers
    log_info "Controllers:"
    python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-controllers 2>/dev/null | \
        jq -r '.[] | "  - \(.hostname) (\(.ip_address)) - VIP Owner: \(.vip_owner)"' || echo "  (unable to list controllers)"

    # Get enabled services on current node
    log_info "Services on this node:"
    python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-controllers 2>/dev/null | \
        jq -r --arg ip "$current_ip" '.[] | select(.ip_address == $ip) | .services | to_entries[] | select(.value == true) | "  - \(.key)"' || echo "  (unable to list services)"

    echo ""
}

# Function to show execution plan
show_execution_plan() {
    log_info "=== Execution Plan ==="

    if [[ -n "$SPECIFIC_PHASE" ]]; then
        local phase_num
        phase_num=$(normalize_phase "$SPECIFIC_PHASE")
        log_info "Mode: Single Phase Execution"
        log_info "Phase: $phase_num (${PHASE_NAMES[$phase_num]})"
    else
        log_info "Mode: Full Cluster Setup"
        log_info "Phases to execute:"

        for phase_num in {0..8}; do
            if should_skip_phase "$phase_num"; then
                log_warning "  Phase $phase_num (${PHASE_NAMES[$phase_num]}) - SKIPPED"
            else
                log_info "  Phase $phase_num (${PHASE_NAMES[$phase_num]})"
            fi
        done
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN MODE: No changes will be made"
    fi

    if [[ "$FORCE" == true ]]; then
        log_warning "FORCE MODE: Will overwrite existing configurations"
    fi

    echo ""
}

# Function to confirm execution
confirm_execution() {
    if [[ "$AUTO_CONFIRM" == true ]]; then
        return 0
    fi

    echo -ne "${YELLOW}Do you want to proceed? (yes/no): ${NC}"
    read -r response

    if [[ "$response" != "yes" && "$response" != "y" ]]; then
        log_info "Execution cancelled by user"
        exit 0
    fi
}

# Function to setup passwordless sudo on remote nodes
setup_remote_passwordless_sudo() {
    log_info "Configuring passwordless sudo on all remote nodes..."

    # Get all compute nodes from YAML
    local all_nodes=$(python3 << EOPY
import yaml, json
with open('$CONFIG_PATH', 'r') as f:
    config = yaml.safe_load(f)

nodes = []

# Controllers
for ctrl in config.get('nodes', {}).get('controllers', []):
    nodes.append({
        'hostname': ctrl['hostname'],
        'ip': ctrl['ip_address'],
        'user': ctrl.get('ssh_user', 'koopark')
    })

# Compute nodes
for node in config.get('nodes', {}).get('compute_nodes', []):
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark')
    })

print(json.dumps(nodes))
EOPY
)

    # Get SSH password from YAML cluster_info.ssh_password
    local ssh_password=$(python3 << EOPY
import yaml
with open('$CONFIG_PATH', 'r') as f:
    config = yaml.safe_load(f)
print(config.get('cluster_info', {}).get('ssh_password', ''))
EOPY
)

    # Check if sshpass is available
    local has_sshpass=false
    if command -v sshpass &> /dev/null; then
        has_sshpass=true
    fi

    local success_count=0
    local failed_count=0
    local total_count=0

    # Get all local IPs for skip checking
    local local_ips=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$')
    log_info "  Local IPs: $(echo $local_ips | tr '\n' ' ')"

    # Count total nodes
    total_count=$(echo "$all_nodes" | jq 'length')
    log_info "  Total nodes to configure: $total_count"

    while IFS= read -r node_json; do
        local hostname=$(echo "$node_json" | jq -r '.hostname')
        local ip=$(echo "$node_json" | jq -r '.ip')
        local user=$(echo "$node_json" | jq -r '.user')

        # Skip current node (check against all local IPs)
        local is_local=false
        for local_ip in $local_ips; do
            if [[ "$ip" == "$local_ip" ]]; then
                is_local=true
                break
            fi
        done

        if [[ "$is_local" == "true" ]]; then
            log_info "  Skipping current node: $hostname ($ip)"
            continue
        fi

        log_info "  Configuring passwordless sudo on $hostname ($ip)..."

        # Check if already configured
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$ip" \
            "sudo -n true" 2>/dev/null; then
            log_success "  $hostname: Already configured"
            success_count=$((success_count + 1))
            continue
        fi

        # Setup passwordless sudo remotely - try without password first
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$ip" \
            "echo '$user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$user > /dev/null && \
             sudo chmod 440 /etc/sudoers.d/$user" 2>/dev/null; then
            log_success "  $hostname: Configured successfully"
            success_count=$((success_count + 1))
        else
            # Try with sshpass if password is configured in YAML
            if [[ -n "$ssh_password" && "$has_sshpass" == "true" ]]; then
                log_info "  $hostname: Using ssh_password from YAML config..."
                if sshpass -p "$ssh_password" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$ip" \
                    "echo '$ssh_password' | sudo -S sh -c \"echo '$user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$user && chmod 440 /etc/sudoers.d/$user\"" 2>/dev/null; then
                    log_success "  $hostname: Configured successfully (with YAML password)"
                    success_count=$((success_count + 1))
                    continue
                fi
            elif [[ -n "$ssh_password" && "$has_sshpass" == "false" ]]; then
                log_warning "  sshpass not installed. Installing..."
                apt-get install -y sshpass > /dev/null 2>&1 || yum install -y sshpass > /dev/null 2>&1 || true
                if command -v sshpass &> /dev/null; then
                    has_sshpass=true
                    if sshpass -p "$ssh_password" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$user@$ip" \
                        "echo '$ssh_password' | sudo -S sh -c \"echo '$user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$user && chmod 440 /etc/sudoers.d/$user\"" 2>/dev/null; then
                        log_success "  $hostname: Configured successfully (with YAML password)"
                        success_count=$((success_count + 1))
                        continue
                    fi
                fi
            fi

            # Fallback: Try with TTY allocation for interactive password input
            log_warning "  $hostname: Needs sudo password. Please enter password for $user@$ip:"
            if ssh -t -o ConnectTimeout=30 -o StrictHostKeyChecking=no "$user@$ip" \
                "echo '$user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$user > /dev/null && \
                 sudo chmod 440 /etc/sudoers.d/$user" 2>&1; then
                log_success "  $hostname: Configured successfully (with password)"
                success_count=$((success_count + 1))
            else
                log_warning "  $hostname: Failed (may need manual setup)"
                failed_count=$((failed_count + 1))
            fi
        fi

    done < <(echo "$all_nodes" | jq -c '.[]')

    log_info "Passwordless sudo setup summary:"
    log_info "  - Successful: $success_count nodes"
    if [[ $failed_count -gt 0 ]]; then
        log_warning "  - Failed: $failed_count nodes (continuing anyway)"
    fi
}

# Function to execute Phase 0: Infrastructure
execute_phase_0() {
    log_phase "0" "Basic Infrastructure Setup"

    log_info "Verifying parser and utilities..."

    # Test parser
    if python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" validate; then
        log_success "Configuration parser verified"
    else
        log_error "Configuration parser failed"
        return 1
    fi

    # Test auto-discovery
    if [[ -x "$SCRIPT_DIR/discovery/auto_discovery.sh" ]]; then
        log_success "Auto-discovery script found"
    else
        log_error "Auto-discovery script not found or not executable"
        return 1
    fi

    # Test cluster_info
    if [[ -x "$SCRIPT_DIR/utils/cluster_info.sh" ]]; then
        log_success "Cluster info utility found"
    else
        log_error "Cluster info utility not found or not executable"
        return 1
    fi

    # Setup SSH passwordless authentication for all nodes
    log_info "Setting up SSH passwordless authentication..."
    local ssh_setup_script="$PROJECT_ROOT/setup_ssh_passwordless_multihead.sh"
    if [[ -x "$ssh_setup_script" ]]; then
        if bash "$ssh_setup_script" "$CONFIG_PATH"; then
            log_success "SSH passwordless authentication configured"
        else
            log_warning "SSH passwordless setup encountered issues (continuing)"
        fi
    else
        log_warning "SSH passwordless setup script not found: $ssh_setup_script"
    fi

    # Setup passwordless sudo on remote nodes
    log_info "Setting up passwordless sudo on all nodes..."
    setup_remote_passwordless_sudo

    log_success "Phase 0 completed: Basic infrastructure ready"
    return 0
}

# Function to execute a phase
execute_phase() {
    local phase_num=$1
    local phase_name=${PHASE_NAMES[$phase_num]}
    local phase_script=${PHASE_SCRIPTS[$phase_num]}

    log_phase "$phase_num" "$phase_name Setup"

    # Special handling for Phase 0 and 7
    if [[ "$phase_num" == "0" ]]; then
        execute_phase_0
        return $?
    fi

    if [[ "$phase_num" == "7" ]]; then
        log_info "Phase 7 (Backup System) has no setup - utilities already created"
        log_success "Phase 7 completed: Backup utilities available"
        return 0
    fi

    # Check if script exists
    local script_path="$SCRIPT_DIR/$phase_script"
    if [[ ! -f "$script_path" ]]; then
        log_error "Phase script not found: $script_path"
        return 1
    fi

    # Make script executable
    chmod +x "$script_path"

    # Build command with options
    local cmd="$script_path --config $CONFIG_PATH"

    if [[ "$DRY_RUN" == true ]]; then
        cmd="$cmd --dry-run"
    fi

    if [[ "$FORCE" == true ]]; then
        cmd="$cmd --force"
    fi

    if [[ "$phase_num" == "6" && "$SKIP_SSL" == true ]]; then
        cmd="$cmd --skip-ssl"
    fi

    # Phase 4 (Slurm): Auto-deploy to compute nodes
    if [[ "$phase_num" == "4" ]]; then
        cmd="$cmd --auto-deploy-compute"
    fi

    # Execute phase script
    log_info "Executing: $cmd"

    if eval "$cmd"; then
        log_success "Phase $phase_num completed successfully"
        return 0
    else
        log_error "Phase $phase_num failed"
        return 1
    fi
}

# Function to wait between phases
wait_between_phases() {
    local seconds=5

    if [[ "$DRY_RUN" == true ]]; then
        seconds=1
    fi

    log_info "Waiting ${seconds}s before next phase..."
    sleep "$seconds"
}

# Function to verify phase completion
verify_phase() {
    local phase_num=$1

    log_info "Verifying Phase $phase_num completion..."

    case "$phase_num" in
        0)
            # Verify parser works
            python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" validate &>/dev/null
            ;;
        1)
            # Verify GlusterFS
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet glusterd 2>/dev/null
            else
                return 0
            fi
            ;;
        2)
            # Verify MariaDB
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet mariadb 2>/dev/null
            else
                return 0
            fi
            ;;
        3)
            # Verify Redis
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet redis-server 2>/dev/null || \
                systemctl is-active --quiet redis 2>/dev/null
            else
                return 0
            fi
            ;;
        4)
            # Verify Slurm
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet slurmctld 2>/dev/null
            else
                return 0
            fi
            ;;
        5)
            # Verify Keepalived
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet keepalived 2>/dev/null
            else
                return 0
            fi
            ;;
        6)
            # Verify Nginx
            if [[ "$DRY_RUN" == false ]]; then
                systemctl is-active --quiet nginx 2>/dev/null
            else
                return 0
            fi
            ;;
        7)
            # Verify backup scripts exist
            [[ -x "$SCRIPT_DIR/backup/backup.sh" ]] && \
            [[ -x "$SCRIPT_DIR/backup/restore.sh" ]]
            ;;
    esac

    return $?
}

# Function to check cluster nodes status
check_cluster_nodes_status() {
    # Use the dedicated Python script that shows all nodes (controllers + compute)
    if [[ -f "$SCRIPT_DIR/check_all_nodes.py" ]]; then
        python3 "$SCRIPT_DIR/check_all_nodes.py" --config "$CONFIG_PATH" || {
            log_warning "Failed to run node status checker"
            return 1
        }
    else
        log_warning "Node status checker script not found: $SCRIPT_DIR/check_all_nodes.py"
        return 1
    fi
}

# Function to display summary
display_summary() {
    local total_phases=$1
    local successful_phases=$2
    local failed_phases=$3

    echo ""
    log_info "=== Execution Summary ==="
    log_info "Total phases: $total_phases"
    log_success "Successful: $successful_phases"

    if [[ $failed_phases -gt 0 ]]; then
        log_error "Failed: $failed_phases"
    fi

    echo ""

    if [[ $failed_phases -eq 0 ]]; then
        log_success "All phases completed successfully!"
        log_info "Cluster setup complete. Next steps:"
        log_info "  1. Verify cluster status: ./utils/cluster_info.sh --config $CONFIG_PATH"
        log_info "  2. Check web services: ./utils/web_health_check.sh"
        log_info "  3. Test job submission: srun hostname"
        log_info "  4. Access web interface: https://$(python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-value web.domain 2>/dev/null || echo 'cluster.example.com')"
    else
        log_error "Some phases failed. Please check the logs at $LOG_FILE"
        log_info "To retry failed phases, run:"
        log_info "  sudo ./start_multihead.sh --phase <phase_number>"
    fi

    # Display cluster nodes status
    check_cluster_nodes_status
}

# Function to handle errors
handle_error() {
    local phase=$1
    local error_code=$2

    log_error "Phase $phase failed with exit code $error_code"

    if [[ "$AUTO_CONFIRM" == true ]]; then
        log_error "Auto-confirm mode: stopping execution"
        exit "$error_code"
    fi

    echo -ne "${YELLOW}Continue with next phase anyway? (yes/no): ${NC}"
    read -r response

    if [[ "$response" != "yes" && "$response" != "y" ]]; then
        log_info "Execution stopped by user"
        exit "$error_code"
    fi

    log_warning "Continuing despite error..."
}

# Function to run cleanup phase (Phase -1)
run_cleanup_phase() {
    local cleanup_script="$SCRIPT_DIR/setup/phase_pre_cleanup.sh"

    if [[ ! -f "$cleanup_script" ]]; then
        log_warning "Cleanup script not found: $cleanup_script"
        log_warning "Skipping pre-setup cleanup (not recommended for production)"
        return 0
    fi

    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_phase "-1" "Pre-Setup Cleanup & Validation"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""

    # Make script executable
    chmod +x "$cleanup_script"

    # Build cleanup command with appropriate options
    local cleanup_cmd="$cleanup_script --config $CONFIG_PATH"

    if [[ "$DRY_RUN" == true ]]; then
        cleanup_cmd="$cleanup_cmd --dry-run"
    fi

    if [[ "$AUTO_CONFIRM" == true ]] || [[ "$FORCE" == true ]]; then
        cleanup_cmd="$cleanup_cmd --force"
    fi

    # Execute cleanup
    log_info "Executing: $cleanup_cmd"

    if eval "$cleanup_cmd"; then
        log_success "Pre-setup cleanup completed"
        log_info ""
        return 0
    else
        local exit_code=$?
        log_error "Pre-setup cleanup failed (exit code: $exit_code)"

        if [[ "$AUTO_CONFIRM" == true ]]; then
            log_error "Cannot continue with failed cleanup in auto-confirm mode"
            exit $exit_code
        fi

        echo -ne "${YELLOW}Continue anyway? (not recommended) (yes/no): ${NC}"
        read -r response

        if [[ "$response" != "yes" ]]; then
            log_info "Setup cancelled by user"
            exit $exit_code
        fi

        log_warning "Continuing without cleanup (may encounter conflicts)"
        return 0
    fi
}

# Main execution function
main() {
    parse_args "$@"

    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║      Multi-Head HPC Cluster Setup Orchestration           ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Starting at: $(date)"
    log_info "Log file: $LOG_FILE"
    echo ""

    check_root
    check_prerequisites

    # Run cleanup phase BEFORE any setup (ensures idempotent execution)
    run_cleanup_phase

    display_cluster_info
    show_execution_plan
    confirm_execution

    echo ""
    log_info "=== Beginning Cluster Setup ==="
    echo ""

    local total_phases=0
    local successful_phases=0
    local failed_phases=0

    if [[ -n "$SPECIFIC_PHASE" ]]; then
        # Execute single phase
        local phase_num
        phase_num=$(normalize_phase "$SPECIFIC_PHASE")

        total_phases=1

        if execute_phase "$phase_num"; then
            successful_phases=$((successful_phases + 1))

            if verify_phase "$phase_num"; then
                log_success "Phase $phase_num verification passed"
            else
                log_warning "Phase $phase_num verification failed (but execution succeeded)"
            fi
        else
            failed_phases=$((failed_phases + 1))
        fi
    else
        # Execute all phases (except skipped ones)
        for phase_num in {0..8}; do
            if should_skip_phase "$phase_num"; then
                log_warning "Skipping Phase $phase_num (${PHASE_NAMES[$phase_num]})"
                continue
            fi

            total_phases=$((total_phases + 1))

            if execute_phase "$phase_num"; then
                successful_phases=$((successful_phases + 1))

                if verify_phase "$phase_num"; then
                    log_success "Phase $phase_num verification passed"
                else
                    log_warning "Phase $phase_num verification failed (but execution succeeded)"
                fi

                # Wait between phases (except after last phase)
                if [[ $phase_num -lt 8 ]]; then
                    wait_between_phases
                fi
            else
                local phase_exit_code=$?
                failed_phases=$((failed_phases + 1))
                handle_error "$phase_num" $phase_exit_code
            fi

            echo ""
        done
    fi

    display_summary "$total_phases" "$successful_phases" "$failed_phases"

    log_info "Finished at: $(date)"

    # Exit with error if any phases failed
    if [[ $failed_phases -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

# Run main function
main "$@"
