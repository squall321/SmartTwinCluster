#!/bin/bash
###############################################################################
# Cluster Information Display Utility
#
# Purpose: Display multi-head cluster status in user-friendly format
# Usage: ./cluster_info.sh [--config CONFIG_PATH] [--format FORMAT]
###############################################################################

set -euo pipefail

# Default values
CONFIG_PATH="../my_multihead_cluster.yaml"
FORMAT="table"  # table, json, compact
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVERY_SH="${SCRIPT_DIR}/../discovery/auto_discovery.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --config PATH    Path to my_multihead_cluster.yaml (default: ../my_multihead_cluster.yaml)"
            echo "  --format FORMAT  Output format: table, json, compact (default: table)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run auto-discovery
echo -e "${CYAN}🔍 Discovering cluster nodes...${NC}" >&2
DISCOVERY_JSON=$(bash "$DISCOVERY_SH" --config "$CONFIG_PATH" --timeout 2 2>/dev/null)

# Extract information
CLUSTER_NAME=$(echo "$DISCOVERY_JSON" | jq -r '.config_path' | xargs basename | sed 's/.yaml//')
TOTAL=$(echo "$DISCOVERY_JSON" | jq -r '.total_controllers')
ACTIVE=$(echo "$DISCOVERY_JSON" | jq -r '.active_controllers')
INACTIVE=$(echo "$DISCOVERY_JSON" | jq -r '.inactive_controllers')
VIP=$(echo "$DISCOVERY_JSON" | jq -r '.vip')
VIP_OWNER=$(echo "$DISCOVERY_JSON" | jq -r '.vip_owner // "none"')
CLUSTER_STATE=$(echo "$DISCOVERY_JSON" | jq -r '.cluster_state')
TIMESTAMP=$(echo "$DISCOVERY_JSON" | jq -r '.timestamp')

# Output based on format
case $FORMAT in
    json)
        echo "$DISCOVERY_JSON" | jq '.'
        ;;

    compact)
        echo -e "${BOLD}Cluster:${NC} $CLUSTER_NAME | ${BOLD}State:${NC} $CLUSTER_STATE | ${BOLD}Active:${NC} $ACTIVE/$TOTAL | ${BOLD}VIP:${NC} $VIP ($VIP_OWNER)"
        ;;

    table|*)
        # Print header
        echo ""
        echo "========================================"
        echo -e "${BOLD}HPC Portal Multi-Head Cluster Status${NC}"
        echo "========================================"
        echo -e "${BOLD}Cluster Name:${NC} $CLUSTER_NAME"
        echo -e "${BOLD}Cluster Size:${NC} $TOTAL-node"

        # Cluster state with color
        case $CLUSTER_STATE in
            healthy)
                echo -e "${BOLD}Cluster State:${NC} ${GREEN}$CLUSTER_STATE${NC}"
                ;;
            degraded)
                echo -e "${BOLD}Cluster State:${NC} ${YELLOW}$CLUSTER_STATE${NC}"
                ;;
            down)
                echo -e "${BOLD}Cluster State:${NC} ${RED}$CLUSTER_STATE${NC}"
                ;;
            *)
                echo -e "${BOLD}Cluster State:${NC} $CLUSTER_STATE"
                ;;
        esac

        echo -e "${BOLD}VIP:${NC} $VIP (owned by ${GREEN}$VIP_OWNER${NC})"
        echo -e "${BOLD}Active/Total:${NC} $ACTIVE/$TOTAL controllers"
        echo -e "${BOLD}Timestamp:${NC} $TIMESTAMP"
        echo ""

        # Controller status table
        echo -e "${BOLD}Controller Status:${NC}"
        echo "+------------+---------------+----------+--------+-----+-----+-----+-----+-----+"
        echo "| Hostname   | IP            | Status   | Load   | GFS | MDB | RDS | SLM | WEB |"
        echo "+------------+---------------+----------+--------+-----+-----+-----+-----+-----+"

        for i in $(seq 0 $(($TOTAL - 1))); do
            CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")

            HOSTNAME=$(echo "$CTRL" | jq -r '.hostname')
            IP=$(echo "$CTRL" | jq -r '.ip')
            STATUS=$(echo "$CTRL" | jq -r '.status')
            LOAD=$(echo "$CTRL" | jq -r '.load // "N/A"')

            # Service status symbols
            GFS_STATUS="✗"
            MDB_STATUS="✗"
            RDS_STATUS="✗"
            SLM_STATUS="✗"
            WEB_STATUS="✗"

            if [[ "$STATUS" == "active" ]]; then
                # Check each service
                SERVICES=$(echo "$CTRL" | jq -r '.services')

                if [[ $(echo "$SERVICES" | jq -e '.glusterfs') ]]; then
                    if [[ $(echo "$SERVICES" | jq -r '.glusterfs.status') == "ok" ]]; then
                        GFS_STATUS="✓"
                    fi
                fi

                if [[ $(echo "$SERVICES" | jq -e '.mariadb') ]]; then
                    if [[ $(echo "$SERVICES" | jq -r '.mariadb.status') == "ok" ]]; then
                        MDB_STATUS="✓"
                    fi
                fi

                if [[ $(echo "$SERVICES" | jq -e '.redis') ]]; then
                    if [[ $(echo "$SERVICES" | jq -r '.redis.status') == "ok" ]]; then
                        RDS_STATUS="✓"
                    fi
                fi

                if [[ $(echo "$SERVICES" | jq -e '.slurm') ]]; then
                    if [[ $(echo "$SERVICES" | jq -r '.slurm.status') == "ok" ]]; then
                        SLM_STATUS="✓"
                    fi
                fi

                if [[ $(echo "$SERVICES" | jq -e '.web') ]]; then
                    if [[ $(echo "$SERVICES" | jq -r '.web.status') == "ok" ]]; then
                        WEB_STATUS="✓"
                    fi
                fi
            fi

            # Format status with color
            if [[ "$STATUS" == "active" ]]; then
                STATUS_COLORED="${GREEN}Active${NC}  "
            else
                STATUS_COLORED="${RED}Inactive${NC}"
                LOAD="N/A"
            fi

            printf "| %-10s | %-13s | %-17b | %-6s |  %1s  |  %1s  |  %1s  |  %1s  |  %1s  |\n" \
                   "$HOSTNAME" "$IP" "$STATUS_COLORED" "$LOAD" "$GFS_STATUS" "$MDB_STATUS" "$RDS_STATUS" "$SLM_STATUS" "$WEB_STATUS"
        done

        echo "+------------+---------------+----------+--------+-----+-----+-----+-----+-----+"
        echo "GFS=GlusterFS, MDB=MariaDB, RDS=Redis, SLM=Slurm, WEB=Web Services"
        echo ""

        # Service details (only if active controllers exist)
        if [[ $ACTIVE -gt 0 ]]; then
            echo -e "${BOLD}Service Details:${NC}"

            # GlusterFS
            GLUSTERFS_COUNT=0
            GLUSTERFS_OK=0
            for i in $(seq 0 $(($TOTAL - 1))); do
                CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")
                if [[ $(echo "$CTRL" | jq -e '.services.glusterfs') ]]; then
                    GLUSTERFS_COUNT=$((GLUSTERFS_COUNT + 1))
                    if [[ $(echo "$CTRL" | jq -r '.services.glusterfs.status') == "ok" ]]; then
                        GLUSTERFS_OK=$((GLUSTERFS_OK + 1))
                    fi
                fi
            done
            if [[ $GLUSTERFS_COUNT -gt 0 ]]; then
                echo -e "  - GlusterFS: ${GREEN}$GLUSTERFS_OK${NC}/$GLUSTERFS_COUNT nodes"
            fi

            # MariaDB Galera
            MARIADB_COUNT=0
            MARIADB_OK=0
            MARIADB_CLUSTER_SIZE=0
            for i in $(seq 0 $(($TOTAL - 1))); do
                CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")
                if [[ $(echo "$CTRL" | jq -e '.services.mariadb') ]]; then
                    MARIADB_COUNT=$((MARIADB_COUNT + 1))
                    if [[ $(echo "$CTRL" | jq -r '.services.mariadb.status') == "ok" ]]; then
                        MARIADB_OK=$((MARIADB_OK + 1))
                        MARIADB_CLUSTER_SIZE=$(echo "$CTRL" | jq -r '.services.mariadb.cluster_size')
                    fi
                fi
            done
            if [[ $MARIADB_COUNT -gt 0 ]]; then
                if [[ $MARIADB_CLUSTER_SIZE -gt 0 ]]; then
                    echo -e "  - MariaDB Galera: ${GREEN}$MARIADB_OK${NC}/$MARIADB_COUNT nodes (Cluster size: $MARIADB_CLUSTER_SIZE)"
                else
                    echo -e "  - MariaDB Galera: ${YELLOW}$MARIADB_OK${NC}/$MARIADB_COUNT nodes (Not clustered)"
                fi
            fi

            # Redis Cluster
            REDIS_COUNT=0
            REDIS_OK=0
            for i in $(seq 0 $(($TOTAL - 1))); do
                CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")
                if [[ $(echo "$CTRL" | jq -e '.services.redis') ]]; then
                    REDIS_COUNT=$((REDIS_COUNT + 1))
                    if [[ $(echo "$CTRL" | jq -r '.services.redis.status') == "ok" ]]; then
                        REDIS_OK=$((REDIS_OK + 1))
                    fi
                fi
            done
            if [[ $REDIS_COUNT -gt 0 ]]; then
                echo -e "  - Redis Cluster: ${GREEN}$REDIS_OK${NC}/$REDIS_COUNT nodes"
            fi

            # Slurm
            SLURM_COUNT=0
            SLURM_PRIMARY=""
            SLURM_BACKUPS=0
            for i in $(seq 0 $(($TOTAL - 1))); do
                CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")
                HOSTNAME=$(echo "$CTRL" | jq -r '.hostname')
                if [[ $(echo "$CTRL" | jq -e '.services.slurm') ]]; then
                    SLURM_COUNT=$((SLURM_COUNT + 1))
                    if [[ $(echo "$CTRL" | jq -r '.services.slurm.status') == "ok" ]]; then
                        ROLE=$(echo "$CTRL" | jq -r '.services.slurm.role')
                        if [[ "$ROLE" == "primary" ]]; then
                            SLURM_PRIMARY="$HOSTNAME"
                        elif [[ "$ROLE" == "backup" ]]; then
                            SLURM_BACKUPS=$((SLURM_BACKUPS + 1))
                        fi
                    fi
                fi
            done
            if [[ $SLURM_COUNT -gt 0 ]]; then
                if [[ -n "$SLURM_PRIMARY" ]]; then
                    echo -e "  - Slurm: Primary on ${GREEN}$SLURM_PRIMARY${NC} ($SLURM_BACKUPS backups ready)"
                else
                    echo -e "  - Slurm: ${YELLOW}No primary controller${NC}"
                fi
            fi

            # Web services
            WEB_COUNT=0
            WEB_OK=0
            for i in $(seq 0 $(($TOTAL - 1))); do
                CTRL=$(echo "$DISCOVERY_JSON" | jq ".controllers[$i]")
                if [[ $(echo "$CTRL" | jq -e '.services.web') ]]; then
                    WEB_COUNT=$((WEB_COUNT + 1))
                    if [[ $(echo "$CTRL" | jq -r '.services.web.status') == "ok" ]]; then
                        WEB_OK=$((WEB_OK + 1))
                    fi
                fi
            done
            if [[ $WEB_COUNT -gt 0 ]]; then
                echo -e "  - Web Services: ${GREEN}$WEB_OK${NC}/$WEB_COUNT nodes running"
            fi

            echo ""
        fi

        echo "========================================"
        ;;
esac
