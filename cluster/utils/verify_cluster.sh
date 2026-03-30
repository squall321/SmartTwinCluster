#!/bin/bash
################################################################################
# Post-Installation Cluster Verification Script
#
# Checks all critical services and reports health status.
# Run after setup_cluster_full_multihead_offline.sh completes.
#
# Usage: sudo ./verify_cluster.sh [--config CONFIG_FILE]
################################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
check_warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; WARN=$((WARN+1)); }
check_fail() { echo -e "  ${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }

echo ""
echo -e "${BOLD}=== HPC Cluster Post-Installation Verification ===${NC}"
echo -e "Date: $(date)"
echo ""

################################################################################
# 1. Slurm Services
################################################################################
echo -e "${CYAN}[1/7] Slurm Services${NC}"

if command -v sinfo &>/dev/null || [[ -x /usr/local/slurm/bin/sinfo ]]; then
    check_pass "sinfo binary found"
else
    check_fail "sinfo binary not found"
fi

if systemctl is-active --quiet slurmctld 2>/dev/null; then
    check_pass "slurmctld is running"
else
    check_warn "slurmctld is not running (may be on another controller)"
fi

if command -v sinfo &>/dev/null; then
    idle_nodes=$(sinfo -h -t idle -N 2>/dev/null | wc -l)
    down_nodes=$(sinfo -h -t down,drain,unknown -N 2>/dev/null | wc -l)
    total_nodes=$(sinfo -h -N 2>/dev/null | wc -l)

    if [[ $down_nodes -gt 0 ]]; then
        check_warn "Slurm nodes: $idle_nodes idle, $down_nodes unhealthy (total: $total_nodes)"
    elif [[ $total_nodes -gt 0 ]]; then
        check_pass "All $total_nodes Slurm nodes healthy"
    else
        check_warn "No Slurm nodes registered"
    fi
fi
echo ""

################################################################################
# 2. Munge Authentication
################################################################################
echo -e "${CYAN}[2/7] Munge Authentication${NC}"

if systemctl is-active --quiet munge 2>/dev/null; then
    check_pass "munge service is running"
else
    check_fail "munge service is not running"
fi

if [[ -f /etc/munge/munge.key ]]; then
    perms=$(stat -c "%a" /etc/munge/munge.key 2>/dev/null)
    owner=$(stat -c "%U:%G" /etc/munge/munge.key 2>/dev/null)
    if [[ "$perms" == "400" && "$owner" == "munge:munge" ]]; then
        check_pass "munge.key permissions correct ($perms, $owner)"
    else
        check_warn "munge.key permissions: $perms $owner (expected 400 munge:munge)"
    fi
else
    check_fail "munge.key not found"
fi

if command -v munge &>/dev/null; then
    if munge -n 2>/dev/null | unmunge 2>&1 | grep -q "STATUS.*Success"; then
        check_pass "munge encode/decode test passed"
    else
        check_fail "munge encode/decode test failed"
    fi
fi
echo ""

################################################################################
# 3. MariaDB / Galera
################################################################################
echo -e "${CYAN}[3/7] MariaDB / Galera${NC}"

if systemctl is-active --quiet mariadb 2>/dev/null; then
    check_pass "MariaDB is running"

    cluster_size=$(mysql -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')
    if [[ -n "$cluster_size" && "$cluster_size" -gt 0 ]]; then
        check_pass "Galera cluster size: $cluster_size"
    else
        check_warn "Galera cluster status unknown (may require auth)"
    fi
else
    check_warn "MariaDB is not running (may be on another controller)"
fi
echo ""

################################################################################
# 4. Redis
################################################################################
echo -e "${CYAN}[4/7] Redis${NC}"

if systemctl is-active --quiet redis-server 2>/dev/null || systemctl is-active --quiet redis 2>/dev/null; then
    check_pass "Redis is running"

    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/6379" 2>/dev/null; then
        check_pass "Redis port 6379 responding"
    else
        check_warn "Redis port 6379 not responding"
    fi
else
    check_warn "Redis is not running (may be on another controller)"
fi
echo ""

################################################################################
# 5. GlusterFS
################################################################################
echo -e "${CYAN}[5/7] GlusterFS${NC}"

if systemctl is-active --quiet glusterd 2>/dev/null; then
    check_pass "GlusterFS daemon is running"

    volumes=$(gluster volume list 2>/dev/null | wc -l)
    if [[ $volumes -gt 0 ]]; then
        check_pass "GlusterFS volumes: $volumes"
    else
        check_warn "No GlusterFS volumes found"
    fi
else
    check_warn "GlusterFS is not running (may not be configured)"
fi
echo ""

################################################################################
# 6. Keepalived
################################################################################
echo -e "${CYAN}[6/7] Keepalived${NC}"

if systemctl is-active --quiet keepalived 2>/dev/null; then
    check_pass "Keepalived is running"
else
    check_warn "Keepalived is not running (may be on another controller)"
fi
echo ""

################################################################################
# 7. Web Services (Port Check)
################################################################################
echo -e "${CYAN}[7/7] Web Services${NC}"

declare -A service_ports=(
    [auth_portal_4430]=4430
    [auth_portal_4431]=4431
    [backend_5010]=5010
    [websocket_5011]=5011
    [kooCAEWeb_5173]=5173
    [saml_idp_7000]=7000
    [nginx_80]=80
    [nginx_443]=443
)

for svc in "${!service_ports[@]}"; do
    port=${service_ports[$svc]}
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        check_pass "$svc (port $port)"
    else
        check_warn "$svc (port $port) not responding"
    fi
done
echo ""

################################################################################
# Summary
################################################################################
echo -e "${BOLD}=== Verification Summary ===${NC}"
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some checks FAILED. Review the output above.${NC}"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo -e "${YELLOW}All critical checks passed with $WARN warning(s).${NC}"
    exit 0
else
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
fi
