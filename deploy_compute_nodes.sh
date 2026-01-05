#!/bin/bash
################################################################################
# Compute Node Deployment Script (Phase 10 Wrapper)
#
# Description:
#   Deploys offline packages and services to all compute nodes.
#   This is a standalone wrapper for Phase 10 of the cluster setup.
#
# Deployed Components:
#   - APT packages (offline)
#   - Slurm (slurmd)
#   - Munge authentication
#   - GlusterFS client + autofs
#
# Usage:
#   sudo ./deploy_compute_nodes.sh [OPTIONS]
#
# Options:
#   --config PATH        Path to YAML configuration file (default: my_multihead_cluster.yaml)
#   --node HOSTNAME      Deploy to specific node only
#   --parallel N         Number of parallel deployments (default: 3)
#   --dry-run            Preview actions without executing
#   --force              Force deployment even if already configured
#   --yes, -y            Skip confirmation prompts
#   --help               Show this help message
#
# Examples:
#   # Deploy to all compute nodes
#   sudo ./deploy_compute_nodes.sh
#
#   # Deploy to specific node
#   sudo ./deploy_compute_nodes.sh --node compute001
#
#   # Deploy with custom config
#   sudo ./deploy_compute_nodes.sh --config /path/to/cluster.yaml
#
#   # Preview deployment (dry-run)
#   sudo ./deploy_compute_nodes.sh --dry-run
#
# Author: Claude Code
# Date: 2025-01-05
################################################################################

set -euo pipefail

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE10_SCRIPT="${SCRIPT_DIR}/cluster/setup/phase10_compute_deploy.sh"

# Default config
DEFAULT_CONFIG="${SCRIPT_DIR}/my_multihead_cluster.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if phase10 script exists
if [[ ! -f "$PHASE10_SCRIPT" ]]; then
    log_error "Phase 10 script not found: $PHASE10_SCRIPT"
    exit 1
fi

# Parse arguments to find config or set default
CONFIG_ARG=""
PASS_ARGS=()
HAS_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_ARG="$2"
            HAS_CONFIG=true
            PASS_ARGS+=("$1" "$2")
            shift 2
            ;;
        --help|-h)
            echo ""
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║       Compute Node Deployment (Phase 10)                       ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
            grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//' | head -40
            exit 0
            ;;
        *)
            PASS_ARGS+=("$1")
            shift
            ;;
    esac
done

# Use default config if not specified
if [[ "$HAS_CONFIG" == false ]]; then
    if [[ -f "$DEFAULT_CONFIG" ]]; then
        CONFIG_ARG="$DEFAULT_CONFIG"
        PASS_ARGS=("--config" "$CONFIG_ARG" "${PASS_ARGS[@]}")
        log_info "Using default config: $DEFAULT_CONFIG"
    else
        log_error "No config file specified and default not found: $DEFAULT_CONFIG"
        log_error "Usage: $0 --config <path_to_yaml>"
        exit 1
    fi
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    echo "Usage: sudo $0 [OPTIONS]"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       Compute Node Deployment (Phase 10)                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Config: $CONFIG_ARG"
log_info "Script: $PHASE10_SCRIPT"
echo ""

# Make executable and run
chmod +x "$PHASE10_SCRIPT"
exec bash "$PHASE10_SCRIPT" "${PASS_ARGS[@]}"
