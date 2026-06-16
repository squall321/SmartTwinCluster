#!/bin/bash
################################################################################
# 웹유저 ↔ Slurm role-account/qos association 동기화 (멱등)
#
# YAML(my_multihead_cluster.yaml)의
#   - roles.definitions          (role 3종: admin/poweruser/user 의 상한/qos)
#   - sso.group_role_mapping     (그룹→role 매핑, default_role)
#   - users.cluster_users        (실제 클러스터 사용자)
# 를 읽어 각 role 에 대해 다음을 멱등하게 동기화한다:
#   1) role_qos     : sacctmgr add|modify qos role-<role>
#                     (MaxTRESPerJob/Priority 로 role 상한 인코딩)
#   2) role-account : sacctmgr add account role-<role>   (존재시 skip)
#   3) association  : 각 cluster_user 를 그 role 의 account/qos 에 등록
#                     (DefaultQOS + qos), 존재시 skip
#
# 멱등 패턴: 모두 'show 후 없으면 add, 있으면 modify|skip'
#            (slurm_config_manager.create_or_update_qos 패턴 차용)
#
# 사용법 (헤드노드에서 실행):
#   sudo ./sync_role_associations.sh [--config YAML] [--dry-run] [--yes]
#
# 옵션:
#   --config FILE   클러스터 YAML (기본: my_multihead_cluster.yaml)
#   --dry-run       실제 실행 없이, 실행할 sacctmgr 명령만 출력
#   --yes / -y      확인 프롬프트 없이 진행 (비대화형/CI)
#
# role 상한 (MaxTRESPerJob / Priority):
#   YAML roles.definitions.<role> 에 max_cpu / max_nodes / priority 키가
#   있으면 그것을 쓰고, 없으면 아래 내장 기본값을 사용한다(기존 YAML 무수정 동작).
#     admin     : MaxTRESPerJob 무제한(-1)      Priority=1000
#     poweruser : MaxTRESPerJob cpu=512,node=4  Priority=500
#     user      : MaxTRESPerJob cpu=128,node=1  Priority=100
################################################################################

set -uo pipefail   # 주의: set -e 미사용 ( ((counter++)) / show-miss 비정상종료 방지 )

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── sacctmgr 절대경로 (소스빌드 우선, 패키지 폴백; bare 이름 금지) ──────────────
SACCTMGR="/usr/local/slurm/bin/sacctmgr"
[[ ! -x "$SACCTMGR" ]] && SACCTMGR="/opt/slurm/bin/sacctmgr"
[[ ! -x "$SACCTMGR" ]] && SACCTMGR="/usr/bin/sacctmgr"
SUDO="/usr/bin/sudo"

CONFIG_FILE="my_multihead_cluster.yaml"
DRY_RUN=false
ASSUME_YES=false

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --yes|-y)   ASSUME_YES=true; shift ;;
        --help|-h)
            sed -n '2,40p' "$0" | grep -v '^####' | sed 's/^# \?//'
            exit 0 ;;
        *)
            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# 프로젝트 루트 (cluster/utils/ 기준 2단계 상위)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
YAML_PATH="$PROJECT_ROOT/$CONFIG_FILE"

if [[ ! -f "$YAML_PATH" ]]; then
    log_error "설정 파일 없음: $YAML_PATH"
    exit 1
fi

# dry-run 이 아니면 root 필요 (sudo sacctmgr 사용)
if [[ "$DRY_RUN" == "false" && $EUID -ne 0 ]]; then
    log_error "root 권한 필요 (sudo 사용). 미리보기는 --dry-run 사용."
    exit 1
fi

# ── YAML 파싱 (python3 인라인; 기존 스크립트 패턴) ────────────────────────────
# 출력 포맷 (탭 구분, 멱등 처리용 한 줄=한 레코드):
#   ROLE\t<role>\t<priority>\t<maxtres>      ← role 3종 (maxtres="" 면 무제한)
#   USER\t<username>\t<role>                  ← 유저→role 배정
# 정렬: ROLE 먼저, USER 나중.
parse_yaml() {
    python3 -c '
import sys, yaml

with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f) or {}

roles_def = ((cfg.get("roles") or {}).get("definitions") or {})
sso = cfg.get("sso") or {}
grp_role = sso.get("group_role_mapping") or {}
default_role = sso.get("default_role") or "user"
users = ((cfg.get("users") or {}).get("cluster_users") or [])

VALID = ("admin", "poweruser", "user")

# role 상한 내장 기본값 (YAML 에 max_cpu/max_nodes/priority 없을 때)
DEFAULTS = {
    "admin":     {"priority": 1000, "max_cpu": None, "max_nodes": None},  # 무제한
    "poweruser": {"priority": 500,  "max_cpu": 512,  "max_nodes": 4},
    "user":      {"priority": 100,  "max_cpu": 128,  "max_nodes": 1},
}

def maxtres(role, d):
    # YAML override 우선, 없으면 내장 기본값
    mc = d.get("max_cpu", DEFAULTS[role]["max_cpu"])
    mn = d.get("max_nodes", DEFAULTS[role]["max_nodes"])
    parts = []
    if mc is not None:
        parts.append("cpu=%s" % mc)
    if mn is not None:
        parts.append("node=%s" % mn)
    return ",".join(parts)   # "" 면 무제한

# role 3종 항상 출력 (YAML definitions 에 빠진 role 도 기본값으로 보장)
for role in VALID:
    d = roles_def.get(role) or {}
    prio = d.get("priority", DEFAULTS[role]["priority"])
    print("ROLE\t%s\t%s\t%s" % (role, prio, maxtres(role, d)))

# group_role_mapping / default_role 에 등장하는 role 검증(미지원 role 경고만)
seen = set(grp_role.values()) | {default_role}
for r in sorted(seen):
    if r not in VALID:
        sys.stderr.write("[parse] WARN: 미지원 role \"%s\" (mapping/default) — 무시\n" % r)

# 유저 → role 배정.
# cluster_users 에 명시적 role 키가 있으면 그것을, 없으면 default_role.
for u in users:
    name = u.get("username")
    if not name:
        continue
    role = u.get("role") or default_role
    if role not in VALID:
        sys.stderr.write("[parse] WARN: user %s 의 role \"%s\" 미지원 → default %s\n" % (name, role, default_role))
        role = default_role if default_role in VALID else "user"
    print("USER\t%s\t%s" % (name, role))
' "$YAML_PATH"
}

PARSED="$(parse_yaml)"
if [[ $? -ne 0 || -z "$PARSED" ]]; then
    log_error "YAML 파싱 실패: $YAML_PATH"
    exit 1
fi

# ── 클러스터 이름 (slurm.conf 에서; install_slurm_accounting.sh 패턴) ─────────
CLUSTER_NAME=""
for conf in /usr/local/slurm/etc/slurm.conf /etc/slurm/slurm.conf; do
    if [[ -f "$conf" ]]; then
        CLUSTER_NAME="$(grep -m1 "^ClusterName=" "$conf" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
        [[ -n "$CLUSTER_NAME" ]] && break
    fi
done
[[ -z "$CLUSTER_NAME" ]] && CLUSTER_NAME="mycluster"

log_info "Config:   $YAML_PATH"
log_info "sacctmgr: $SACCTMGR"
log_info "Cluster:  $CLUSTER_NAME"
[[ "$DRY_RUN" == "true" ]] && log_warning "DRY-RUN 모드 — 실제 변경 없음 (명령만 출력)"
echo ""

# ── sacctmgr 래퍼 ────────────────────────────────────────────────────────────
# run_sacctmgr <args...>  : 실제 실행 (sudo). dry-run 이면 명령만 출력하고 0 반환.
# read_sacctmgr <args...> : show/list 류 (read-only). dry-run 이어도 실제 조회.
#                           (멱등 판정에 실제 상태가 필요하므로 항상 조회)
run_sacctmgr() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    [dry-run] $SUDO -n $SACCTMGR -i $*"
        return 0
    fi
    "$SUDO" -n "$SACCTMGR" -i "$@"
}

read_sacctmgr() {
    # dry-run 에서 slurm 미설치면 실패할 수 있음 → 호출부에서 stdout 비었음으로 처리
    "$SUDO" -n "$SACCTMGR" "$@" 2>/dev/null
}

# QoS 존재 여부 (이름 정확 일치)
qos_exists() {
    local name="$1" out
    out="$(read_sacctmgr -n -P show qos "$name" format=Name 2>/dev/null)"
    [[ -n "$out" ]] && grep -qx "$name" <<< "$out"
}

# Account 존재 여부
account_exists() {
    local name="$1" out
    out="$(read_sacctmgr -n -P show account "$name" format=Account 2>/dev/null)"
    [[ -n "$out" ]] && grep -qx "$name" <<< "$out"
}

# 특정 account 에 user association 존재 여부
assoc_exists() {
    local user="$1" account="$2" out
    out="$(read_sacctmgr -n -P show assoc user="$user" account="$account" format=User,Account 2>/dev/null)"
    [[ -n "$out" ]] && grep -qx "${user}|${account}" <<< "$out"
}

# ── 1) role_qos 생성/갱신 (멱등) ─────────────────────────────────────────────
sync_qos() {
    local role="$1" priority="$2" maxtres="$3"
    local qos="role-${role}"

    log_info "[QoS] $qos (Priority=$priority, MaxTRESPerJob=${maxtres:-<unlimited>})"

    if qos_exists "$qos"; then
        log_info "       이미 존재 → modify"
    else
        log_info "       없음 → add"
        run_sacctmgr add qos "$qos" || { log_error "       add qos $qos 실패"; return 1; }
    fi

    # Priority 갱신 (멱등: 항상 modify set)
    run_sacctmgr modify qos "$qos" set "Priority=${priority}" \
        || { log_error "       modify Priority 실패"; return 1; }

    # MaxTRESPerJob 갱신. 비었으면(admin 무제한) -1 로 제한 해제.
    local mt="${maxtres}"
    [[ -z "$mt" ]] && mt="-1"
    run_sacctmgr modify qos "$qos" set "MaxTRESPerJob=${mt}" \
        || { log_error "       modify MaxTRESPerJob 실패"; return 1; }

    log_success "       $qos 동기화 완료"
    return 0
}

# ── 2) role-account 생성 (멱등, 존재시 skip) ─────────────────────────────────
sync_account() {
    local role="$1"
    local account="role-${role}"

    if account_exists "$account"; then
        log_info "[Account] $account 이미 존재 → skip"
        return 0
    fi

    log_info "[Account] $account 없음 → add"
    run_sacctmgr add account "$account" \
        Cluster="$CLUSTER_NAME" \
        Description="Web role: ${role}" \
        Organization="role-${role}" \
        || { log_error "          add account $account 실패"; return 1; }
    log_success "          $account 생성 완료"
    return 0
}

# ── 3) user → role account/qos association (멱등) ────────────────────────────
sync_user() {
    local user="$1" role="$2"
    local account="role-${role}"
    local qos="role-${role}"

    if assoc_exists "$user" "$account"; then
        log_info "[Assoc] $user @ $account 이미 존재 → skip"
        return 0
    fi

    log_info "[Assoc] $user → account=$account DefaultQOS=$qos qos=$qos"
    run_sacctmgr add user "$user" \
        account="$account" \
        DefaultQOS="$qos" \
        qos="$qos" \
        || { log_error "        add user $user 실패"; return 1; }
    log_success "        $user association 완료"
    return 0
}

# ── 확인 프롬프트 (대화형일 때만; read -p 비대화형 EOF 회피) ──────────────────
if [[ "$DRY_RUN" == "false" && "$ASSUME_YES" == "false" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "위 role/account/qos 동기화를 진행할까요? (y/N): " ans
        case "$ans" in
            [Yy]*) ;;
            *) log_warning "취소됨"; exit 0 ;;
        esac
    else
        log_error "비대화형 환경 — --yes 또는 --dry-run 플래그 필요"
        exit 1
    fi
fi

# ── 메인 루프 ────────────────────────────────────────────────────────────────
FAIL=0

# 먼저 ROLE 레코드(qos+account), 그다음 USER 레코드(association) 순서로 처리.
while IFS=$'\t' read -r kind a b c; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "ROLE" ]]; then
        sync_qos "$a" "$b" "$c"     || FAIL=$((FAIL + 1))
        sync_account "$a"           || FAIL=$((FAIL + 1))
    fi
done <<< "$PARSED"

echo ""
while IFS=$'\t' read -r kind a b c; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "USER" ]]; then
        sync_user "$a" "$b"         || FAIL=$((FAIL + 1))
    fi
done <<< "$PARSED"

echo ""
if [[ "$FAIL" -gt 0 ]]; then
    log_warning "=== 완료 (실패 ${FAIL}건) ==="
    exit 1
fi
log_success "=== role-account/qos association 동기화 완료 ==="
[[ "$DRY_RUN" == "true" ]] && log_info "실제 적용: --dry-run 빼고 sudo 로 재실행"
exit 0
