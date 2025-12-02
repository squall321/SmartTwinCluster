#!/bin/bash

#############################################################################
# Wait for slurmctld to be ready
#
# This script waits for slurmctld to become responsive after a restart
# Useful for automation scripts and CI/CD pipelines
#
# Usage:
#   ./wait_for_slurmctld.sh [max_attempts] [wait_seconds]
#
# Examples:
#   ./wait_for_slurmctld.sh           # Default: 10 attempts, 2 seconds each
#   ./wait_for_slurmctld.sh 20 1      # 20 attempts, 1 second each
#   ./wait_for_slurmctld.sh 5 5       # 5 attempts, 5 seconds each
#
# Exit codes:
#   0 - slurmctld is ready
#   1 - slurmctld failed to become ready
#############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
MAX_ATTEMPTS=${1:-10}
WAIT_TIME=${2:-2}

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

wait_for_slurmctld() {
    log_info "Waiting for slurmctld to be ready (max ${MAX_ATTEMPTS} attempts, ${WAIT_TIME}s each)..."

    local attempt=1

    while [ $attempt -le $MAX_ATTEMPTS ]; do
        log_info "Attempt $attempt/$MAX_ATTEMPTS: Checking slurmctld connectivity..."

        # Test if slurmctld is responding
        if /usr/local/slurm/bin/scontrol ping &>/dev/null; then
            log_success "slurmctld is responsive (via scontrol ping)"
            return 0
        elif /usr/local/slurm/bin/sinfo &>/dev/null; then
            log_success "slurmctld is responsive (via sinfo)"
            return 0
        else
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                log_warning "slurmctld not ready yet, waiting ${WAIT_TIME}s..."
                sleep $WAIT_TIME
                attempt=$((attempt + 1))
            else
                log_error "slurmctld failed to become ready after $MAX_ATTEMPTS attempts"
                log_error "Total wait time: $((MAX_ATTEMPTS * WAIT_TIME)) seconds"
                return 1
            fi
        fi
    done

    return 1
}

# Main
if wait_for_slurmctld; then
    log_success "slurmctld is ready!"
    exit 0
else
    log_error "slurmctld is not ready!"
    log_info "Troubleshooting steps:"
    echo "  1. Check if slurmctld is running: sudo systemctl status slurmctld"
    echo "  2. Check slurmctld logs: sudo tail -100 /var/log/slurm/slurmctld.log"
    echo "  3. Check network connectivity: ping localhost"
    echo "  4. Check slurm configuration: /usr/local/slurm/bin/scontrol show config"
    exit 1
fi
