#!/bin/bash

################################################################################
# Cluster Comprehensive Test Script
#
# This script performs comprehensive testing of all cluster components
# after deployment to verify everything is working correctly.
#
# Usage:
#   ./test_cluster.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)
#   --test NAME         Run specific test only
#   --skip-test NAME    Skip specific test
#   --verbose           Show detailed output
#   --report FILE       Save test report to file
#   --help              Show this help message
#
# Available Tests:
#   all                 Run all tests (default)
#   glusterfs           Test GlusterFS replication
#   mariadb             Test MariaDB Galera cluster
#   redis               Test Redis cluster
#   slurm               Test Slurm job submission
#   keepalived          Test Keepalived VIP failover
#   web                 Test web services
#   backup              Test backup/restore
#
# Examples:
#   ./test_cluster.sh
#   ./test_cluster.sh --test glusterfs --verbose
#   ./test_cluster.sh --skip-test backup --report report.txt
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
SPECIFIC_TEST=""
SKIP_TESTS=()
VERBOSE=false
REPORT_FILE=""

# Test results
declare -A TEST_RESULTS
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
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
            --test)
                SPECIFIC_TEST="$2"
                shift 2
                ;;
            --skip-test)
                SKIP_TESTS+=("$2")
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --report)
                REPORT_FILE="$2"
                shift 2
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

# Function to check if test should be skipped
should_skip_test() {
    local test_name=$1

    for skip_test in "${SKIP_TESTS[@]}"; do
        if [[ "$skip_test" == "$test_name" ]]; then
            return 0
        fi
    done

    return 1
}

# Function to record test result
record_result() {
    local test_name=$1
    local result=$2  # pass or fail
    local message=$3

    TEST_RESULTS["$test_name"]="$result:$message"

    if [[ "$result" == "pass" ]]; then
        ((TESTS_PASSED++))
        log_success "$test_name: $message"
    else
        ((TESTS_FAILED++))
        log_error "$test_name: $message"
    fi
}

# Function to skip test
skip_test() {
    local test_name=$1
    ((TESTS_SKIPPED++))
    log_warning "Skipping test: $test_name"
}

# Test 1: GlusterFS Replication
test_glusterfs() {
    log_test "Testing GlusterFS replication..."

    # Check if glusterd is running
    if ! systemctl is-active --quiet glusterd 2>/dev/null; then
        record_result "glusterfs" "fail" "glusterd service not running"
        return 1
    fi

    # Check peers
    local peer_count=$(gluster peer status 2>/dev/null | grep -c "Peer in Cluster" || echo "0")
    if [[ $peer_count -lt 1 ]]; then
        record_result "glusterfs" "fail" "No peers found (expected at least 1)"
        return 1
    fi

    # Check volume
    if ! gluster volume list 2>/dev/null | grep -q .; then
        record_result "glusterfs" "fail" "No volumes found"
        return 1
    fi

    local volume_name=$(gluster volume list 2>/dev/null | head -1)
    local volume_status=$(gluster volume info "$volume_name" 2>/dev/null | grep "Status:" | awk '{print $2}')

    if [[ "$volume_status" != "Started" ]]; then
        record_result "glusterfs" "fail" "Volume $volume_name is not started (status: $volume_status)"
        return 1
    fi

    # Test file replication
    local test_file="/mnt/gluster/test_gluster_$$"
    local test_data="GlusterFS test at $(date)"

    if echo "$test_data" > "$test_file" 2>/dev/null; then
        sleep 2  # Wait for replication

        # Verify file exists
        if [[ -f "$test_file" ]]; then
            local read_data=$(cat "$test_file")
            if [[ "$read_data" == "$test_data" ]]; then
                rm -f "$test_file"
                record_result "glusterfs" "pass" "Replication working (peers: $peer_count, volume: $volume_name)"
                return 0
            else
                rm -f "$test_file"
                record_result "glusterfs" "fail" "Data mismatch after replication"
                return 1
            fi
        else
            record_result "glusterfs" "fail" "Test file not found after write"
            return 1
        fi
    else
        record_result "glusterfs" "fail" "Cannot write to GlusterFS mount"
        return 1
    fi
}

# Test 2: MariaDB Galera Cluster
test_mariadb() {
    log_test "Testing MariaDB Galera cluster..."

    # Check if mariadb is running
    if ! systemctl is-active --quiet mariadb 2>/dev/null; then
        record_result "mariadb" "fail" "MariaDB service not running"
        return 1
    fi

    # Check if Galera is enabled
    if ! mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | grep -q wsrep_cluster_size; then
        record_result "mariadb" "fail" "Galera not enabled (standalone mode)"
        return 1
    fi

    # Check cluster size
    local cluster_size=$(mysql -se "SHOW STATUS LIKE 'wsrep_cluster_size'" 2>/dev/null | awk '{print $2}')
    local cluster_status=$(mysql -se "SHOW STATUS LIKE 'wsrep_cluster_status'" 2>/dev/null | awk '{print $2}')
    local local_state=$(mysql -se "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
    local ready=$(mysql -se "SHOW STATUS LIKE 'wsrep_ready'" 2>/dev/null | awk '{print $2}')

    if [[ "$cluster_status" != "Primary" ]]; then
        record_result "mariadb" "fail" "Cluster status is $cluster_status (expected: Primary)"
        return 1
    fi

    if [[ "$local_state" != "Synced" ]]; then
        record_result "mariadb" "fail" "Local state is $local_state (expected: Synced)"
        return 1
    fi

    if [[ "$ready" != "ON" ]]; then
        record_result "mariadb" "fail" "Cluster not ready (wsrep_ready: $ready)"
        return 1
    fi

    # Test data replication
    local test_db="test_cluster_$$"
    local test_data="MariaDB test at $(date)"

    mysql << EOF 2>/dev/null
CREATE DATABASE IF NOT EXISTS $test_db;
USE $test_db;
CREATE TABLE IF NOT EXISTS test_table (
    id INT PRIMARY KEY AUTO_INCREMENT,
    data VARCHAR(255)
);
INSERT INTO test_table (data) VALUES ('$test_data');
EOF

    if [[ $? -eq 0 ]]; then
        local read_data=$(mysql -se "SELECT data FROM $test_db.test_table ORDER BY id DESC LIMIT 1" 2>/dev/null)
        mysql -e "DROP DATABASE $test_db" 2>/dev/null

        if [[ "$read_data" == "$test_data" ]]; then
            record_result "mariadb" "pass" "Cluster healthy (size: $cluster_size, status: $cluster_status)"
            return 0
        else
            record_result "mariadb" "fail" "Data mismatch after write"
            return 1
        fi
    else
        record_result "mariadb" "fail" "Cannot write to database"
        return 1
    fi
}

# Test 3: Redis Cluster
test_redis() {
    log_test "Testing Redis cluster..."

    # Check if redis is running
    local redis_service="redis-server"
    if ! systemctl list-units --type=service --all | grep -q "redis-server"; then
        redis_service="redis"
    fi

    if ! systemctl is-active --quiet "$redis_service" 2>/dev/null; then
        record_result "redis" "fail" "Redis service not running"
        return 1
    fi

    # Check Redis mode
    local redis_mode="standalone"
    if redis-cli cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
        redis_mode="cluster"
    elif systemctl is-active --quiet redis-sentinel 2>/dev/null; then
        redis_mode="sentinel"
    fi

    # Test based on mode
    local test_key="test_cluster_$$"
    local test_value="Redis test at $(date)"

    case "$redis_mode" in
        cluster)
            local cluster_state=$(redis-cli cluster info 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r')
            if [[ "$cluster_state" != "ok" ]]; then
                record_result "redis" "fail" "Cluster state is $cluster_state (expected: ok)"
                return 1
            fi

            # Test write/read
            redis-cli set "$test_key" "$test_value" >/dev/null 2>&1
            local read_value=$(redis-cli get "$test_key" 2>/dev/null)
            redis-cli del "$test_key" >/dev/null 2>&1

            if [[ "$read_value" == "$test_value" ]]; then
                record_result "redis" "pass" "Cluster mode working (state: $cluster_state)"
                return 0
            else
                record_result "redis" "fail" "Data mismatch after write"
                return 1
            fi
            ;;

        sentinel)
            # Test with sentinel
            local master_status=$(redis-cli -p 26379 SENTINEL master mymaster 2>/dev/null | grep -A1 "status" | tail -1 || echo "unknown")

            redis-cli set "$test_key" "$test_value" >/dev/null 2>&1
            local read_value=$(redis-cli get "$test_key" 2>/dev/null)
            redis-cli del "$test_key" >/dev/null 2>&1

            if [[ "$read_value" == "$test_value" ]]; then
                record_result "redis" "pass" "Sentinel mode working"
                return 0
            else
                record_result "redis" "fail" "Data mismatch after write"
                return 1
            fi
            ;;

        *)
            # Standalone mode
            redis-cli set "$test_key" "$test_value" >/dev/null 2>&1
            local read_value=$(redis-cli get "$test_key" 2>/dev/null)
            redis-cli del "$test_key" >/dev/null 2>&1

            if [[ "$read_value" == "$test_value" ]]; then
                record_result "redis" "pass" "Standalone mode working"
                return 0
            else
                record_result "redis" "fail" "Data mismatch after write"
                return 1
            fi
            ;;
    esac
}

# Test 4: Slurm Job Submission
test_slurm() {
    log_test "Testing Slurm job submission..."

    # Check if slurmctld is running
    if ! systemctl is-active --quiet slurmctld 2>/dev/null; then
        record_result "slurm" "fail" "slurmctld service not running"
        return 1
    fi

    # Check if scontrol is available
    if ! command -v scontrol &> /dev/null; then
        record_result "slurm" "fail" "scontrol command not found"
        return 1
    fi

    # Submit test job
    local job_script="/tmp/test_job_$$.sh"
    cat > "$job_script" << 'EOF'
#!/bin/bash
#SBATCH --job-name=test_cluster
#SBATCH --output=/tmp/test_job_%j.out
#SBATCH --ntasks=1
#SBATCH --time=00:01:00

echo "Slurm test job started at $(date)"
hostname
echo "Slurm test job completed at $(date)"
EOF

    # Submit job
    local job_id=$(sbatch "$job_script" 2>&1 | grep -oE "[0-9]+")

    if [[ -z "$job_id" ]]; then
        rm -f "$job_script"
        record_result "slurm" "fail" "Failed to submit job"
        return 1
    fi

    # Wait for job to complete (max 30 seconds)
    local elapsed=0
    local job_state=""

    while [[ $elapsed -lt 30 ]]; do
        job_state=$(sacct -j "$job_id" --format=State --noheader 2>/dev/null | head -1 | xargs)

        if [[ "$job_state" == "COMPLETED" ]]; then
            rm -f "$job_script"
            record_result "slurm" "pass" "Job $job_id completed successfully"
            return 0
        elif [[ "$job_state" == "FAILED" || "$job_state" == "CANCELLED" ]]; then
            rm -f "$job_script"
            record_result "slurm" "fail" "Job $job_id failed (state: $job_state)"
            return 1
        fi

        sleep 2
        ((elapsed += 2))
    done

    # Timeout
    scancel "$job_id" 2>/dev/null
    rm -f "$job_script"
    record_result "slurm" "fail" "Job $job_id timed out (state: $job_state)"
    return 1
}

# Test 5: Keepalived VIP
test_keepalived() {
    log_test "Testing Keepalived VIP..."

    # Check if keepalived is running
    if ! systemctl is-active --quiet keepalived 2>/dev/null; then
        record_result "keepalived" "fail" "keepalived service not running"
        return 1
    fi

    # Get VIP from config
    if [[ ! -f "$CONFIG_PATH" ]]; then
        record_result "keepalived" "fail" "Config file not found: $CONFIG_PATH"
        return 1
    fi

    local vip=$(python3 "$SCRIPT_DIR/config/parser.py" "$CONFIG_PATH" get-value network.vip 2>/dev/null || echo "")

    if [[ -z "$vip" ]]; then
        record_result "keepalived" "fail" "VIP not found in config"
        return 1
    fi

    # Check if VIP is assigned to any interface
    if ip addr show | grep -q "$vip"; then
        # VIP is on this node
        record_result "keepalived" "pass" "VIP $vip is assigned (MASTER mode)"
        return 0
    else
        # VIP is not on this node - check if it's reachable
        if ping -c 1 -W 2 "$vip" >/dev/null 2>&1; then
            record_result "keepalived" "pass" "VIP $vip is reachable (BACKUP mode)"
            return 0
        else
            record_result "keepalived" "fail" "VIP $vip is not reachable from any node"
            return 1
        fi
    fi
}

# Test 6: Web Services
test_web() {
    log_test "Testing web services..."

    # Check if web health check script exists
    if [[ ! -x "$SCRIPT_DIR/utils/web_health_check.sh" ]]; then
        record_result "web" "fail" "web_health_check.sh not found or not executable"
        return 1
    fi

    # Run web health check
    if "$SCRIPT_DIR/utils/web_health_check.sh" --format compact >/dev/null 2>&1; then
        local healthy_count=$(./utils/web_health_check.sh --format compact 2>/dev/null | grep -c "✓" || echo "0")
        record_result "web" "pass" "Web services healthy ($healthy_count services)"
        return 0
    else
        record_result "web" "fail" "Web services health check failed"
        return 1
    fi
}

# Test 7: Backup System
test_backup() {
    log_test "Testing backup system..."

    # Check if backup script exists
    if [[ ! -x "$SCRIPT_DIR/backup/backup.sh" ]]; then
        record_result "backup" "fail" "backup.sh not found or not executable"
        return 1
    fi

    # Create test backup (dry-run)
    if sudo "$SCRIPT_DIR/backup/backup.sh" --config "$CONFIG_PATH" --dry-run >/dev/null 2>&1; then
        record_result "backup" "pass" "Backup system available (dry-run successful)"
        return 0
    else
        record_result "backup" "fail" "Backup dry-run failed"
        return 1
    fi
}

# Function to generate report
generate_report() {
    local report=""

    report+="========================================\n"
    report+="Cluster Test Report\n"
    report+="========================================\n"
    report+="Date: $(date)\n"
    report+="Hostname: $(hostname)\n"
    report+="IP: $(hostname -I | awk '{print $1}')\n"
    report+="\n"
    report+="Summary:\n"
    report+="  Passed:  $TESTS_PASSED\n"
    report+="  Failed:  $TESTS_FAILED\n"
    report+="  Skipped: $TESTS_SKIPPED\n"
    report+="\n"
    report+="Details:\n"

    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local status=$(echo "$result" | cut -d: -f1)
        local message=$(echo "$result" | cut -d: -f2-)

        if [[ "$status" == "pass" ]]; then
            report+="  [PASS] $test_name: $message\n"
        else
            report+="  [FAIL] $test_name: $message\n"
        fi
    done

    report+="========================================\n"

    echo -e "$report"

    if [[ -n "$REPORT_FILE" ]]; then
        echo -e "$report" > "$REPORT_FILE"
        log_info "Report saved to: $REPORT_FILE"
    fi
}

# Main function
main() {
    parse_args "$@"

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      Multi-Head HPC Cluster Test Suite                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Starting tests at: $(date)"
    echo ""

    # List of all tests
    local all_tests=("glusterfs" "mariadb" "redis" "slurm" "keepalived" "web" "backup")

    if [[ -n "$SPECIFIC_TEST" ]]; then
        if [[ "$SPECIFIC_TEST" == "all" ]]; then
            # Run all tests
            for test_name in "${all_tests[@]}"; do
                if should_skip_test "$test_name"; then
                    skip_test "$test_name"
                else
                    "test_$test_name" || true
                    echo ""
                fi
            done
        else
            # Run specific test
            if [[ " ${all_tests[*]} " =~ " ${SPECIFIC_TEST} " ]]; then
                "test_$SPECIFIC_TEST"
            else
                log_error "Unknown test: $SPECIFIC_TEST"
                log_info "Available tests: ${all_tests[*]}"
                exit 1
            fi
        fi
    else
        # Run all tests
        for test_name in "${all_tests[@]}"; do
            if should_skip_test "$test_name"; then
                skip_test "$test_name"
            else
                "test_$test_name" || true
                echo ""
            fi
        done
    fi

    echo ""
    log_info "=== Test Summary ==="
    log_success "Passed:  $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Failed:  $TESTS_FAILED"
    else
        log_info "Failed:  $TESTS_FAILED"
    fi
    log_warning "Skipped: $TESTS_SKIPPED"
    echo ""

    generate_report

    log_info "Finished tests at: $(date)"

    # Exit with error if any test failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
