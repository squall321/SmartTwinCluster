#!/bin/bash
################################################################################
# .env 재생성 — yaml(environment 섹션)에서 시크릿을 읽어 각 서비스 .env 채움
#
# 용도:
#   .env 가 없어졌거나(git 추적해제 후 reset/clean), 비번을 yaml 에서 바꾼 뒤
#   각 서비스 .env 를 yaml 단일소스로 다시 만들 때.
#   .env.example(포맷) 을 베이스로 yaml environment 의 시크릿만 치환한다.
#
# 사용법:
#   ./regenerate_env_from_yaml.sh [--config YAML] [--dry-run]
#
# 소스: my_multihead_cluster.yaml 의 environment.{REDIS_PASSWORD,JWT_SECRET_KEY}
################################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

CONFIG_FILE=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^#//;s/^!.*//' | head -18; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# yaml 기본값 (프로젝트 루트의 my_*.yaml)
if [[ -z "$CONFIG_FILE" ]]; then
    for c in "$SCRIPT_DIR/../my_multihead_cluster.yaml" "$SCRIPT_DIR/../my_multihead_cluster_2.yaml"; do
        [[ -f "$c" ]] && { CONFIG_FILE="$c"; break; }
    done
fi
[[ -f "$CONFIG_FILE" ]] || { echo -e "${RED}config 없음: $CONFIG_FILE${NC}"; exit 1; }
echo -e "${BLUE}소스 yaml:${NC} $CONFIG_FILE"

# yaml environment 에서 시크릿/값 읽기
read_yaml() {
    python3 -c "
import yaml
c=yaml.safe_load(open('$CONFIG_FILE')) or {}
env=c.get('environment',{}) or {}
print(env.get('$1','') or '')
" 2>/dev/null
}

REDIS_PASSWORD=$(read_yaml REDIS_PASSWORD)
JWT_SECRET_KEY=$(read_yaml JWT_SECRET_KEY)

[[ -z "$REDIS_PASSWORD" ]] && echo -e "${YELLOW}⚠ environment.REDIS_PASSWORD 비어있음${NC}"
[[ -z "$JWT_SECRET_KEY" ]] && echo -e "${YELLOW}⚠ environment.JWT_SECRET_KEY 비어있음${NC}"
echo "  REDIS_PASSWORD = ${REDIS_PASSWORD:0:2}…(len=${#REDIS_PASSWORD})"
echo "  JWT_SECRET_KEY = ${JWT_SECRET_KEY:0:2}…(len=${#JWT_SECRET_KEY})"
echo ""

# .env 가 있는 서비스: 그 .env 의 시크릿 라인만 yaml 값으로 치환(in-place).
# .env 가 없고 .env.example 만 있으면: example 을 복사 후 시크릿 채움.
# 시크릿 외 다른 값(경로/포트 등)은 건드리지 않는다 — 이미 환경에 맞게 설정돼 있을 수 있음.
patch_one() {
    local svc_dir="${1:-}"
    [[ -z "$svc_dir" ]] && return 0
    local envf="$svc_dir/.env" examplef="$svc_dir/.env.example"
    local src=""
    if [[ -f "$envf" ]]; then
        src="$envf"                       # 기존 .env 의 시크릿만 갱신
    elif [[ -f "$examplef" ]]; then
        echo -e "  ${YELLOW}$envf 없음 → .env.example 에서 생성${NC}"
        [[ "$DRY_RUN" = "0" ]] && cp "$examplef" "$envf"
        src="$envf"
    else
        return 0                          # .env / .env.example 둘 다 없으면 스킵
    fi

    if [[ "$DRY_RUN" = "1" ]]; then
        echo "  [dry-run] $envf 의 REDIS_PASSWORD/JWT_SECRET_KEY 를 yaml 값으로 치환"
        return 0
    fi

    # 시크릿 라인이 있으면 치환, 없으면 추가 (REDIS_PASSWORD/JWT_SECRET_KEY 만)
    _set_kv() {
        local key="$1" val="$2" f="$3"
        grep -qE "^${key}=" "$f" 2>/dev/null \
            && sed -i "s|^${key}=.*|${key}=${val}|" "$f" \
            || echo "${key}=${val}" >> "$f"
    }
    [[ -n "$REDIS_PASSWORD" ]] && grep -qE '^REDIS_PASSWORD=' "$src" && _set_kv REDIS_PASSWORD "$REDIS_PASSWORD" "$src"
    [[ -n "$JWT_SECRET_KEY" ]] && grep -qE '^JWT_SECRET_KEY=' "$src" && _set_kv JWT_SECRET_KEY "$JWT_SECRET_KEY" "$src"
    echo -e "  ${GREEN}✓${NC} $envf"
}

# 시크릿을 쓰는 서비스만 (backend/auth/websocket). frontend 류(VITE_*)는 시크릿 없어 제외.
for d in backend_5010 auth_portal_4430 websocket_5011; do
    [[ -d "$SCRIPT_DIR/$d" ]] && patch_one "$SCRIPT_DIR/$d"
done

echo ""
echo -e "${GREEN}완료.${NC} 적용하려면 백엔드 재시작: ${BLUE}sudo systemctl restart dashboard_backend auth_backend websocket_service${NC}"
