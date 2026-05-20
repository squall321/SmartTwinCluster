#!/bin/bash
################################################################################
# YAML 의도대로 시스템에 반영됐는지 점검
#
# 사용:
#   ./cluster/utils/check_yaml_applied.sh my_multihead_cluster.yaml
#   ./cluster/utils/check_yaml_applied.sh my_multihead_cluster_346.yaml --verbose
################################################################################
set -uo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

YAML="${1:-my_multihead_cluster.yaml}"
VERBOSE=0
[[ "${2:-}" == "--verbose" ]] && VERBOSE=1

[[ ! -f "$YAML" ]] && { echo -e "${RED}❌ YAML 없음: $YAML${NC}"; exit 1; }
YAML=$(readlink -f "$YAML")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${BLUE}═══ YAML 점검: $YAML ═══${NC}"
echo ""

# YAML 키 파싱 (python3 1회 호출로 한 번에)
eval $(python3 - "$YAML" <<'PY'
import sys, yaml, shlex
c = yaml.safe_load(open(sys.argv[1])) or {}
def g(*keys, default=''):
    cur = c
    for k in keys:
        if not isinstance(cur, dict): return default
        cur = cur.get(k, default)
    return cur if cur is not None else default

vals = {
    'CFG_DOMAIN': g('cluster_info', 'domain'),
    'CFG_SSH_USER': g('cluster_info', 'admin_user'),
    'CFG_SSH_PASS_SET': '1' if g('cluster_info','ssh_password') else '0',
    'CFG_PUBLIC_URL': g('public_url') or g('web','public_url') or g('access','public_url'),
    'CFG_SSL_CERT': g('web','ssl','cert_path'),
    'CFG_SSL_KEY':  g('web','ssl','key_path'),
    'CFG_SSO_ENABLED': str(g('sso','enabled', default=False)).lower(),
    'CFG_SSO_TYPE': g('sso','type') or 'saml',
    'CFG_SSO_GROUPS': ','.join((g('sso','group_permissions') or {}).keys()),
    'CFG_SAML_USERS_COUNT': str(len(
        g('web_services','saml','users') or g('saml','test_users') or g('saml','users') or []
    )),
    'CFG_PARTITIONS': ','.join(
        p.get('name','') for p in (g('slurm_config','partitions') or g('slurm','partitions') or [])
    ),
    'CFG_CTRL_COUNT': str(len(g('nodes','controllers') or [])),
    'CFG_CTRL_HOSTS': ','.join(n.get('hostname','') for n in (g('nodes','controllers') or [])),
    'CFG_COMPUTE_COUNT': str(len(g('nodes','compute_nodes') or [])),
    'CFG_REDIS_HOST': g('redis','host') or 'localhost',
    'CFG_GLUSTER_MOUNT': g('shared_storage','glusterfs','mount_point') or '/mnt/gluster',
    'CFG_GLUSTER_SERVER': g('shared_storage','glusterfs','server'),
}
for k, v in vals.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
)

OK=0; FAIL=0; WARN=0
pass()  { echo -e "  ${GREEN}✓${NC} $1"; OK=$((OK+1)); }
fail()  { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN+1)); }
info()  { [[ $VERBOSE -eq 1 ]] && echo -e "    ${BLUE}→${NC} $1" || true; }

###############################################################################
# 1) public_url / 외부 IP
###############################################################################
echo -e "${BLUE}[1] 외부 접속 주소${NC}"
if [[ -n "$CFG_PUBLIC_URL" ]]; then
    pass "YAML public_url: $CFG_PUBLIC_URL"
    # IP vs 도메인 판별
    if [[ "$CFG_PUBLIC_URL" =~ ^[0-9.]+$ ]]; then
        info "IP 형식 — DNS 해석 불필요"
    else
        if getent ahosts "$CFG_PUBLIC_URL" >/dev/null 2>&1; then
            pass "도메인 DNS 해석 OK → $(getent ahosts "$CFG_PUBLIC_URL" | head -1 | awk '{print $1}')"
        else
            warn "도메인 DNS 해석 실패 (사내 DNS 미등록일 수도) — /etc/hosts 확인 필요"
        fi
    fi
else
    fail "YAML 에 public_url 없음 — hostname -I로 fallback됨"
fi

###############################################################################
# 2) SSL 인증서
###############################################################################
echo -e "${BLUE}[2] SSL 인증서${NC}"
SS_CRT="/etc/ssl/certs/nginx-selfsigned.crt"
ACTIVE_CRT=""
if [[ -n "$CFG_SSL_CERT" ]] && [[ -f "$CFG_SSL_CERT" ]]; then
    ACTIVE_CRT="$CFG_SSL_CERT"
    pass "정식 인증서 사용: $CFG_SSL_CERT"
elif [[ -f "$SS_CRT" ]]; then
    ACTIVE_CRT="$SS_CRT"
    info "자체서명 사용: $SS_CRT"
fi

if [[ -n "$ACTIVE_CRT" ]]; then
    CERT_CN=$(openssl x509 -in "$ACTIVE_CRT" -noout -subject 2>/dev/null | sed 's/.*CN *= *//')
    CERT_SAN=$(openssl x509 -in "$ACTIVE_CRT" -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -d ' ')
    info "CN: $CERT_CN"
    info "SAN: $CERT_SAN"
    if [[ -n "$CFG_PUBLIC_URL" ]] && echo "$CERT_CN $CERT_SAN" | grep -qF "$CFG_PUBLIC_URL"; then
        pass "인증서가 public_url($CFG_PUBLIC_URL) 포함"
    elif [[ -n "$CFG_PUBLIC_URL" ]]; then
        fail "인증서가 public_url($CFG_PUBLIC_URL) 미포함 → start_all.sh 재실행"
    fi
else
    fail "인증서 파일 없음"
fi

###############################################################################
# 3) nginx server_name + sites-enabled
###############################################################################
echo -e "${BLUE}[3] nginx${NC}"
NGINX_ENABLED=/etc/nginx/sites-enabled/hpc-portal.conf
if [[ ! -L "$NGINX_ENABLED" && ! -f "$NGINX_ENABLED" ]]; then
    fail "$NGINX_ENABLED 미설치"
else
    REAL_CONF=$(readlink -f "$NGINX_ENABLED")
    pass "활성 conf: $REAL_CONF"
    SERVER_NAMES=$(grep "^[[:space:]]*server_name" "$REAL_CONF" | head -1 | sed 's/.*server_name//;s/;//' | tr -d ' ')
    info "server_name: $SERVER_NAMES"
    if [[ -n "$CFG_PUBLIC_URL" ]] && echo "$SERVER_NAMES" | grep -qF "$CFG_PUBLIC_URL"; then
        pass "server_name 에 public_url 포함"
    elif [[ -n "$CFG_PUBLIC_URL" ]] && echo "$SERVER_NAMES" | grep -q "_"; then
        info "server_name 에 _ (default_server) 만 — IP 모드면 OK"
    else
        warn "server_name 에 public_url 누락 — 도메인 접속 시 매칭 안 될 수 있음"
    fi
fi

if systemctl is-active nginx --quiet; then
    pass "nginx active"
    ss -tln 2>/dev/null | grep -q ":443 " && pass "443 LISTEN" || fail "443 미점유"
else
    fail "nginx inactive"
fi

###############################################################################
# 4) SAML 사용자
###############################################################################
echo -e "${BLUE}[4] SAML 사용자${NC}"
USERS_JSON="${REPO_ROOT}/dashboard/saml_idp_7000/users.json"
if [[ "$CFG_SAML_USERS_COUNT" == "0" ]]; then
    warn "YAML 에 SAML 사용자 정의 없음 → 자동 admin 생성됨"
elif [[ -f "$USERS_JSON" ]]; then
    JSON_COUNT=$(python3 -c "import json; print(len(json.load(open('$USERS_JSON'))))" 2>/dev/null || echo 0)
    if [[ "$JSON_COUNT" == "$CFG_SAML_USERS_COUNT" ]]; then
        pass "YAML($CFG_SAML_USERS_COUNT) ↔ users.json($JSON_COUNT) 일치"
    else
        warn "YAML($CFG_SAML_USERS_COUNT) ↔ users.json($JSON_COUNT) 불일치 — phase5 재실행 필요"
    fi
else
    warn "$USERS_JSON 없음 — phase5_web 미실행"
fi

###############################################################################
# 5) auth_portal_4430 .env
###############################################################################
echo -e "${BLUE}[5] auth_portal_4430 .env${NC}"
AUTH_ENV="${REPO_ROOT}/dashboard/auth_portal_4430/.env"
if [[ -f "$AUTH_ENV" ]]; then
    pass "$AUTH_ENV 존재"
    if [[ -n "$CFG_PUBLIC_URL" ]]; then
        PUB_BASE="https://$CFG_PUBLIC_URL"
        for key in SAML_ACS_URL SAML_SLS_URL CORS_ALLOWED_ORIGINS PUBLIC_URL; do
            VAL=$(grep "^$key=" "$AUTH_ENV" | head -1 | cut -d= -f2-)
            if echo "$VAL" | grep -qF "$CFG_PUBLIC_URL"; then
                info "$key: $VAL ✓"
            else
                warn "$key 가 public_url 미반영: $VAL"
            fi
        done
    fi
else
    fail "$AUTH_ENV 없음 — phase5 미실행"
fi

###############################################################################
# 6) Slurm 파티션
###############################################################################
echo -e "${BLUE}[6] Slurm 파티션${NC}"
if command -v scontrol &>/dev/null; then
    if systemctl is-active slurmctld --quiet; then
        ACTUAL_PARTS=$(scontrol show partitions 2>/dev/null | awk '/PartitionName=/{print $1}' | sed 's/PartitionName=//' | tr '\n' ',' | sed 's/,$//')
        info "YAML:   $CFG_PARTITIONS"
        info "Active: $ACTUAL_PARTS"
        YAML_SET=$(echo "$CFG_PARTITIONS" | tr ',' '\n' | sort -u | tr '\n' ' ')
        ACT_SET=$(echo "$ACTUAL_PARTS" | tr ',' '\n' | sort -u | tr '\n' ' ')
        if [[ "$YAML_SET" == "$ACT_SET" ]]; then
            pass "파티션 일치"
        else
            warn "파티션 불일치 (slurm reconfigure 필요)"
        fi
    else
        warn "slurmctld inactive — 비교 불가"
    fi
else
    info "scontrol 없음 (헤드노드 아님일 수도)"
fi

###############################################################################
# 7) StateSaveLocation 권한
###############################################################################
echo -e "${BLUE}[7] Slurm StateSaveLocation${NC}"
STATE_DIR=$(grep -E '^[[:space:]]*StateSaveLocation' /etc/slurm/slurm.conf 2>/dev/null | head -1 | sed 's/.*=//' | tr -d ' ')
if [[ -n "$STATE_DIR" ]] && [[ -d "$STATE_DIR" ]]; then
    SLURM_UID=$(id -u slurm 2>/dev/null)
    DIR_UID=$(stat -c '%u' "$STATE_DIR")
    if [[ "$DIR_UID" == "$SLURM_UID" ]]; then
        pass "$STATE_DIR owner=slurm OK"
    else
        fail "$STATE_DIR owner UID=$DIR_UID (slurm=$SLURM_UID) — chown 필요"
    fi
elif [[ -n "$STATE_DIR" ]]; then
    fail "$STATE_DIR 디렉토리 없음"
fi

###############################################################################
# 8) 노드 reachable
###############################################################################
echo -e "${BLUE}[8] 노드 SSH${NC}"
if [[ -n "$CFG_CTRL_HOSTS" ]]; then
    CTRL_OK=0; CTRL_BAD=0
    for h in $(echo "$CFG_CTRL_HOSTS" | tr ',' ' '); do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no \
               "$h" 'echo OK' >/dev/null 2>&1; then
            CTRL_OK=$((CTRL_OK+1))
        else
            CTRL_BAD=$((CTRL_BAD+1))
            [[ $VERBOSE -eq 1 ]] && echo "    ✗ $h SSH 실패"
        fi
    done
    [[ $CTRL_BAD -eq 0 ]] && pass "컨트롤러 $CTRL_OK 개 SSH OK" || warn "컨트롤러 SSH: $CTRL_OK OK / $CTRL_BAD FAIL"
fi
info "compute 노드 SSH 전체 점검: cluster/check_all_nodes.py"

###############################################################################
# 9) Redis
###############################################################################
echo -e "${BLUE}[9] Redis${NC}"
if command -v redis-cli &>/dev/null; then
    if redis-cli -h "$CFG_REDIS_HOST" ping 2>/dev/null | grep -q PONG; then
        pass "Redis $CFG_REDIS_HOST ping OK"
    else
        warn "Redis $CFG_REDIS_HOST 응답 없음 (인증 필요할 수도)"
    fi
else
    info "redis-cli 없음"
fi

###############################################################################
# 10) GlusterFS
###############################################################################
echo -e "${BLUE}[10] GlusterFS${NC}"
if mount | grep -q "$CFG_GLUSTER_MOUNT"; then
    pass "$CFG_GLUSTER_MOUNT 마운트됨"
elif [[ -d "$CFG_GLUSTER_MOUNT" ]] && ls "$CFG_GLUSTER_MOUNT" &>/dev/null; then
    pass "$CFG_GLUSTER_MOUNT 접근 가능 (autofs 트리거)"
else
    fail "$CFG_GLUSTER_MOUNT 접근 불가"
fi

###############################################################################
# 요약
###############################################################################
echo ""
echo -e "${BLUE}═══ 결과 ═══${NC}"
echo -e "  ${GREEN}✓ 통과: $OK${NC}"
[[ $WARN -gt 0 ]] && echo -e "  ${YELLOW}⚠ 경고: $WARN${NC}"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}✗ 실패: $FAIL${NC}"

[[ $VERBOSE -eq 0 ]] && echo -e "\n  자세히: $0 $YAML --verbose"

exit $FAIL
