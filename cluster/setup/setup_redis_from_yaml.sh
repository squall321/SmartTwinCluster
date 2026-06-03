#!/bin/bash
################################################################################
# setup_redis_from_yaml.sh — yaml 만 보고 Redis 토폴로지를 (재)설치
#
# 목적:
#   Redis 는 Slurm/GlusterFS 와 무관하므로, 전체 재설치 없이 Redis 만 yaml 기준으로
#   다시 셋업한다. 현재 잘못된 cluster(cluster_state:fail, slots:0)를
#   1 Primary + N Replica + N Sentinel (HA)로 전환한다.
#
# 토폴로지 (yaml redis.type):
#   sentinel   → controllers[0]=master, 나머지=replica, 전 노드 sentinel(quorum=N/2+1)
#   standalone → 단일 master (cluster-enabled no), replica/sentinel 없음
#   (cluster 는 이 스크립트 범위 밖 — phase2_redis.sh --mode cluster 사용)
#
# 특징:
#   - cluster 잔재(cluster-enabled yes, nodes.conf) 자동 정리 후 전환
#   - replicaof/masterauth 를 redis.conf 에 영속(재시작 후에도 유지) — 기존 phase2 의
#     CONFIG SET 휘발 버그 회피
#   - 각 노드에서 개별 실행 (master 먼저 → 그 다음 replica 들)
#   - Slurm/GlusterFS/web 등 다른 phase 는 일절 건드리지 않음
#   - 재실행 가능(idempotent)
#
# 사용법 (각 Redis 노드에서, master 노드부터):
#   sudo ./setup_redis_from_yaml.sh --config my_multihead_cluster.yaml
#   sudo ./setup_redis_from_yaml.sh --config ... --reset   # cluster 잔재 강제 정리
#   sudo ./setup_redis_from_yaml.sh --config ... --dry-run
################################################################################
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARSER="$PROJECT_ROOT/cluster/config/parser.py"

CONFIG_FILE=""
DRY_RUN=false
RESET=false
REDIS_PORT=6379
SENTINEL_PORT=26379
MASTER_NAME="mymaster"

while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --reset) RESET=true; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^#//;s/^!.*//' | head -32; exit 0 ;;
        *) err "Unknown: $1"; exit 1 ;;
    esac
done

[[ $EUID -eq 0 ]] || { err "root 권한 필요 (sudo)"; exit 1; }
if [[ -z "$CONFIG_FILE" ]]; then
    for c in "$PROJECT_ROOT"/my_multihead_cluster.yaml "$PROJECT_ROOT"/my_*.yaml; do
        [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
    done
fi
[[ -f "$CONFIG_FILE" ]] || { err "config 없음: $CONFIG_FILE"; exit 1; }
[[ -f "$PARSER" ]] || { err "parser 없음: $PARSER"; exit 1; }
command -v jq &>/dev/null || { err "jq 필요"; exit 1; }

run() { if [[ "$DRY_RUN" == true ]]; then echo "  [dry-run] $*"; else eval "$@"; fi; }

# ---- yaml 파싱 ----
REDIS_TYPE=$(python3 "$PARSER" --config "$CONFIG_FILE" --get redis.type 2>/dev/null)
[[ -z "$REDIS_TYPE" || "$REDIS_TYPE" == "None" ]] && REDIS_TYPE="sentinel"
REDIS_PASSWORD=$(python3 "$PARSER" --config "$CONFIG_FILE" --get environment.REDIS_PASSWORD 2>/dev/null)
[[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == "None" ]] && { err "environment.REDIS_PASSWORD 없음"; exit 1; }

# redis 튜닝 옵션: yaml 의 여러 위치에서 폴백으로 읽음 (type 무관하게 일관).
# 우선순위: redis.options.<key> → redis.<key> → redis.cluster.<key> → redis.sentinel.<key>
# 비어있으면 기본값 사용. yaml 에 적은 값이 실제 redis.conf 에 반영됨(yaml = 단일소스).
yaml_redis_opt() {
    local key="$1" default="$2" v
    for path in "redis.options.$key" "redis.$key" "redis.cluster.$key" "redis.sentinel.$key"; do
        v=$(python3 "$PARSER" --config "$CONFIG_FILE" --get "$path" 2>/dev/null)
        [[ -n "$v" && "$v" != "None" ]] && { echo "$v"; return; }
    done
    echo "$default"
}
OPT_MAXMEMORY=$(yaml_redis_opt maxmemory "")              # 예 4gb (비면 미설정 = 무제한)
OPT_MAXMEMORY_POLICY=$(yaml_redis_opt maxmemory_policy "allkeys-lru")
OPT_APPENDONLY=$(yaml_redis_opt appendonly "yes")        # True/yes → yes
OPT_APPENDFSYNC=$(yaml_redis_opt appendfsync "everysec")
OPT_MAXCLIENTS=$(yaml_redis_opt maxclients "10000")
OPT_TIMEOUT=$(yaml_redis_opt timeout "0")                # idle 클라 끊기 (0=안끊음)
OPT_TCP_KEEPALIVE=$(yaml_redis_opt tcp_keepalive "300")
OPT_SAVE=$(yaml_redis_opt save "")                       # RDB 스냅샷 규칙 (예 "900 1 300 10")
# python True/False → redis yes/no 정규화
[[ "$OPT_APPENDONLY" =~ ^([Tt]rue|yes|YES)$ ]] && OPT_APPENDONLY="yes" || { [[ "$OPT_APPENDONLY" =~ ^([Ff]alse|no|NO)$ ]] && OPT_APPENDONLY="no"; }

# ---- Sentinel 옵션 (yaml 우선, 없으면 기본값) ----
OPT_SENTINEL_PORT=$(yaml_redis_opt sentinel_port "26379"); SENTINEL_PORT="$OPT_SENTINEL_PORT"
OPT_MASTER_NAME=$(yaml_redis_opt master_name "mymaster"); MASTER_NAME="$OPT_MASTER_NAME"
OPT_DOWN_AFTER=$(yaml_redis_opt down_after_ms "5000")
OPT_FAILOVER_TIMEOUT=$(yaml_redis_opt failover_timeout_ms "10000")
OPT_PARALLEL_SYNCS=$(yaml_redis_opt parallel_syncs "1")
OPT_QUORUM=$(yaml_redis_opt quorum "")                   # 비면 N/2+1 자동

REDIS_CONTROLLERS=$(python3 "$PARSER" --config "$CONFIG_FILE" --service redis 2>/dev/null)
TOTAL=$(echo "$REDIS_CONTROLLERS" | jq '. | length' 2>/dev/null)
[[ -z "$TOTAL" || "$TOTAL" == "0" ]] && { err "redis 노드(services.redis:true) 없음"; exit 1; }

MASTER_IP=$(echo "$REDIS_CONTROLLERS" | jq -r '.[0].ip_address')

# 현재 노드 IP (yaml controllers 중 내 IP) — parser --current 우선, 없으면 hostname -I 교집합
CURRENT_IP=$(python3 "$PARSER" --config "$CONFIG_FILE" --current 2>/dev/null | jq -r '.ip_address // empty' 2>/dev/null)
if [[ -z "$CURRENT_IP" || "$CURRENT_IP" == "None" ]]; then
    for ip in $(hostname -I 2>/dev/null); do
        if echo "$REDIS_CONTROLLERS" | jq -e --arg ip "$ip" '.[] | select(.ip_address==$ip)' &>/dev/null; then
            CURRENT_IP="$ip"; break
        fi
    done
fi
[[ -z "$CURRENT_IP" ]] && { err "현재 노드 IP 를 yaml redis 노드에서 못 찾음 (hostname -I 와 redis 노드 IP 교집합 없음)"; exit 1; }

if [[ -n "$OPT_QUORUM" && "$OPT_QUORUM" != "None" ]]; then QUORUM="$OPT_QUORUM"; else QUORUM=$(( TOTAL / 2 + 1 )); fi
if [[ "$CURRENT_IP" == "$MASTER_IP" ]]; then ROLE="master"; else ROLE="replica"; fi

echo ""
log "config: $CONFIG_FILE"
log "redis.type: $REDIS_TYPE | 노드 ${TOTAL}개 | master=$MASTER_IP | quorum=$QUORUM"
log "이 노드: $CURRENT_IP → ROLE=$ROLE"
[[ "$DRY_RUN" == true ]] && warn "DRY-RUN (실제 변경 없음)"
echo ""

REDIS_CONF="/etc/redis/redis.conf"
[[ -f "$REDIS_CONF" ]] || { err "$REDIS_CONF 없음 — redis-server 미설치?"; exit 1; }

# ---- 1) cluster 잔재 정리 (cluster-enabled yes → no, nodes.conf 제거) ----
cleanup_cluster() {
    log "cluster 잔재 정리..."
    run "systemctl stop redis-server 2>/dev/null || true"
    # cluster-enabled 끄기
    if grep -qE '^cluster-enabled\s+yes' "$REDIS_CONF" 2>/dev/null; then
        run "sed -i 's/^cluster-enabled\s\+yes/cluster-enabled no/' '$REDIS_CONF'"
        ok "  cluster-enabled → no"
    fi
    run "rm -f /var/lib/redis/nodes.conf /var/lib/redis/nodes-*.conf /etc/redis/nodes*.conf"
    ok "  nodes.conf 제거"
}

# redis.conf 에 key value 영속 (있으면 치환, 없으면 추가)
set_conf() {
    local key="$1" val="$2"
    if grep -qE "^${key}\s" "$REDIS_CONF" 2>/dev/null; then
        run "sed -i 's|^${key}\s.*|${key} ${val}|' '$REDIS_CONF'"
    elif grep -qE "^#\s*${key}\s" "$REDIS_CONF" 2>/dev/null; then
        run "sed -i 's|^#\s*${key}\s.*|${key} ${val}|' '$REDIS_CONF'"
    else
        run "echo '${key} ${val}' >> '$REDIS_CONF'"
    fi
}

# ---- 2) 공통 redis.conf (requirepass/masterauth/bind + yaml 튜닝옵션) — 전 노드 ----
configure_redis_common() {
    log "redis.conf 기본 설정 (requirepass/masterauth/bind)..."
    set_conf "requirepass" "$REDIS_PASSWORD"
    set_conf "masterauth"  "$REDIS_PASSWORD"   # failover 후 옛 master 가 replica 로 붙을 때 필요
    set_conf "bind" "0.0.0.0"
    set_conf "protected-mode" "no"
    set_conf "cluster-enabled" "no"
    # yaml 튜닝 옵션 반영 (yaml = 단일소스)
    [[ -n "$OPT_MAXMEMORY" ]] && set_conf "maxmemory" "$OPT_MAXMEMORY"
    set_conf "maxmemory-policy" "$OPT_MAXMEMORY_POLICY"
    set_conf "appendonly" "$OPT_APPENDONLY"
    set_conf "appendfsync" "$OPT_APPENDFSYNC"
    set_conf "maxclients" "$OPT_MAXCLIENTS"
    set_conf "timeout" "$OPT_TIMEOUT"
    set_conf "tcp-keepalive" "$OPT_TCP_KEEPALIVE"
    [[ -n "$OPT_SAVE" && "$OPT_SAVE" != "None" ]] && set_conf "save" "$OPT_SAVE"
    log "  옵션: maxmemory=${OPT_MAXMEMORY:-무제한}/$OPT_MAXMEMORY_POLICY appendonly=$OPT_APPENDONLY/$OPT_APPENDFSYNC maxclients=$OPT_MAXCLIENTS timeout=$OPT_TIMEOUT keepalive=$OPT_TCP_KEEPALIVE"
    ok "  공통 설정 완료"
}

# ---- 3) replica 면 replicaof 영속 ----
configure_replica() {
    log "replica 설정: replicaof $MASTER_IP $REDIS_PORT (영속)..."
    set_conf "replicaof" "$MASTER_IP $REDIS_PORT"
    ok "  replicaof 영속 기록"
}

# ---- 4) master 면 replicaof 제거 (혹시 남아있으면) ----
configure_master() {
    log "master 설정: replicaof 제거(있으면)..."
    run "sed -i '/^replicaof\s/d' '$REDIS_CONF'"
    ok "  master 확정"
}

# ---- 5) sentinel.conf 작성 + 기동 ----
setup_sentinel() {
    log "Sentinel 설치/설정 (port $SENTINEL_PORT, quorum $QUORUM)..."
    case "$(. /etc/os-release 2>/dev/null; echo "$ID")" in
        ubuntu|debian) run "DEBIAN_FRONTEND=noninteractive apt-get install -y redis-sentinel >/dev/null 2>&1 || true" ;;
    esac
    local sconf="/etc/redis/sentinel.conf"
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] $sconf 작성 (monitor $MASTER_NAME $MASTER_IP $REDIS_PORT $QUORUM, announce-ip $CURRENT_IP)"
    else
        cat > "$sconf" <<EOF
# Redis Sentinel (자동생성: setup_redis_from_yaml.sh)
port $SENTINEL_PORT
dir /var/lib/redis
logfile /var/log/redis/sentinel.log
protected-mode no
requirepass $REDIS_PASSWORD

sentinel monitor $MASTER_NAME $MASTER_IP $REDIS_PORT $QUORUM
sentinel auth-pass $MASTER_NAME $REDIS_PASSWORD
sentinel down-after-milliseconds $MASTER_NAME $OPT_DOWN_AFTER
sentinel parallel-syncs $MASTER_NAME $OPT_PARALLEL_SYNCS
sentinel failover-timeout $MASTER_NAME $OPT_FAILOVER_TIMEOUT
sentinel deny-scripts-reconfig yes
sentinel announce-ip $CURRENT_IP
sentinel announce-port $SENTINEL_PORT
EOF
        chown redis:redis "$sconf" 2>/dev/null || true
        chmod 640 "$sconf" 2>/dev/null || true
    fi
    run "systemctl enable redis-sentinel >/dev/null 2>&1 || true"
    run "systemctl restart redis-sentinel"
    ok "  Sentinel 기동"
}

# ==================== 실행 ====================
# cluster 잔재가 있거나 --reset 이면 정리
if [[ "$RESET" == true ]] || grep -qE '^cluster-enabled\s+yes' "$REDIS_CONF" 2>/dev/null; then
    cleanup_cluster
fi

configure_redis_common

case "$REDIS_TYPE" in
    sentinel)
        if [[ "$ROLE" == "master" ]]; then configure_master; else configure_replica; fi
        run "systemctl restart redis-server"
        ok "redis-server 재기동 ($ROLE)"
        setup_sentinel
        ;;
    standalone)
        configure_master
        run "systemctl restart redis-server"
        ok "redis-server 재기동 (standalone)"
        ;;
    *)
        err "redis.type='$REDIS_TYPE' 는 이 스크립트 미지원 (sentinel/standalone). cluster 는 phase2_redis.sh --mode cluster 사용"
        exit 1
        ;;
esac

echo ""
ok "완료 — 이 노드($CURRENT_IP, $ROLE) Redis 설정 적용"
echo ""
if [[ "$ROLE" == "master" ]]; then
    log "다음: 나머지 replica 노드들에서도 이 스크립트를 실행하세요."
    echo "  ssh <replica> 'cd $PROJECT_ROOT && sudo ./cluster/setup/setup_redis_from_yaml.sh --config $CONFIG_FILE'"
fi
log "검증(master 노드에서):"
echo "  redis-cli -p $SENTINEL_PORT -a '<PW>' --no-auth-warning SENTINEL ckquorum $MASTER_NAME"
echo "  redis-cli -h $MASTER_IP -a '<PW>' --no-auth-warning INFO replication | grep -E 'role|connected_slaves'"
