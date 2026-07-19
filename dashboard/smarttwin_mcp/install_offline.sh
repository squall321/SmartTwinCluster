#!/usr/bin/env bash
# smarttwin_mcp 오프라인 설치 — 인터넷 없는 운영서(icn401)에서 MCP 서버 의존성을 repo 동봉
#   wheel 로 설치(offline_packages 패턴, --no-index). dashboard/mcp_slurm/install_offline.sh 를 본뜸.
#
# 사용:
#   ./install_offline.sh                          # venv 만 구축(오프라인, 현재 계정)
#   sudo ./install_offline.sh --install-service   # venv(서비스계정) + systemd 유닛 설치(placeholder 치환)
#
# 계정/경로는 하드코딩하지 않는다:
#   - SERVICE_USER: env SERVICE_USER → YAML web_services.service_user → users.ssh_user
#                   → cluster_info.head_nodes[0].ssh_user → SUDO_USER/whoami
#   - PROJECT_HOME: repo 위치에서 유도(표준 레이아웃 ~/claude/KooSlurmInstallAutomationRefactory)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SERVICE=false
[ "${1:-}" = "--install-service" ] && INSTALL_SERVICE=true

# 0) --install-service 는 root 필요 + SERVICE_USER 를 먼저 유도(venv 를 그 계정으로 생성).
RUN_AS=()   # venv/pip 를 돌릴 계정 prefix (root 면 sudo -u SERVICE_USER)
SERVICE_USER=""
if [ "$INSTALL_SERVICE" = true ]; then
    [ "$EUID" -eq 0 ] || { echo "ERROR: --install-service 는 root(sudo) 필요."; exit 1; }
    SERVICE_USER="${SERVICE_USER:-}"
    if [ -z "$SERVICE_USER" ]; then
        for _yaml in "${CLUSTER_YAML:-}" "$REPO_ROOT/my_multihead_cluster.yaml" "$REPO_ROOT/my_cluster.yaml"; do
            [ -n "$_yaml" ] && [ -f "$_yaml" ] || continue
            SERVICE_USER=$(python3 -c "
import yaml
try:
    c = yaml.safe_load(open('$_yaml')) or {}
    heads = ((c.get('cluster_info') or {}).get('head_nodes') or [])
    head_user = (heads[0].get('ssh_user') if heads and isinstance(heads[0], dict) else '')
    print(((c.get('web_services') or {}).get('service_user')
           or (c.get('users') or {}).get('ssh_user')
           or head_user or ''))
except Exception: pass" 2>/dev/null)
            [ -n "$SERVICE_USER" ] && break
        done
    fi
    [ -n "$SERVICE_USER" ] && id "$SERVICE_USER" &>/dev/null || SERVICE_USER="${SUDO_USER:-$(whoami)}"
    RUN_AS=(sudo -u "$SERVICE_USER")
    echo "[smarttwin_mcp] SERVICE_USER=$SERVICE_USER (group=$(id -gn "$SERVICE_USER"))"
fi

# 1) 파이썬 인터프리터 결정 (3.12 이상 필수 — 운영 기준).
PYBIN=""
for cand in python3.12 python3.13 python3; do
    command -v "$cand" >/dev/null 2>&1 || continue
    _mm="$("$cand" -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [ "$(printf '%s\n3.12\n' "$_mm" | sort -V | head -1)" = "3.12" ]; then PYBIN="$cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "ERROR: python3.12 이상이 필요합니다."; exit 1; }
PY_MM="$("$PYBIN" -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
echo "[smarttwin_mcp] 파이썬: $PYBIN ($PY_MM)"

# 2) wheel 디렉토리 (mcp_slurm 컨벤션: python_wheels/smarttwin_mcp/python<ver>).
CANDIDATES=(
    "$REPO_ROOT/offline_packages_2404/python_wheels/smarttwin_mcp/python${PY_MM}"
    "$REPO_ROOT/offline_packages/python_wheels/smarttwin_mcp/python${PY_MM}"
    "$REPO_ROOT/offline_packages_2404/python_wheels/smarttwin_mcp/python3.12"
)
WHEELDIR=""
for d in "${CANDIDATES[@]}"; do
    [ -d "$d" ] && ls "$d"/*.whl >/dev/null 2>&1 && { WHEELDIR="$d"; break; }
done
[ -n "$WHEELDIR" ] || { echo "ERROR: smarttwin_mcp wheel 디렉토리 없음 (python${PY_MM}). 후보: ${CANDIDATES[*]}"; exit 1; }
echo "[smarttwin_mcp] wheel: $WHEELDIR ($(ls "$WHEELDIR"/*.whl | wc -l) 개)"

# 3) venv + 오프라인 설치 (--no-index, requirements.txt 전체 핀). root 면 SERVICE_USER 로 생성.
VENV_DIR="$SCRIPT_DIR/venv"
[ -d "$VENV_DIR" ] || "${RUN_AS[@]}" "$PYBIN" -m venv "$VENV_DIR"
"${RUN_AS[@]}" "$VENV_DIR/bin/pip" install --no-index --find-links="$WHEELDIR" -r "$SCRIPT_DIR/requirements.txt" \
    && echo "[smarttwin_mcp] ✓ 설치 완료: $VENV_DIR" \
    || { echo "[smarttwin_mcp] ✗ 설치 실패"; exit 1; }

# 4) 검증 — 벤더링 패키지는 PYTHONPATH=src.
PYTHONPATH="$SCRIPT_DIR/src" "$VENV_DIR/bin/python" -c \
    "import fastmcp, smarttwin_mcp.server as s; print('[smarttwin_mcp] ✓ import OK fastmcp', fastmcp.__version__)" \
    || { echo "[smarttwin_mcp] ✗ import 검증 실패"; exit 1; }

[ "$INSTALL_SERVICE" = true ] || {
    echo ""
    echo "다음: systemd 유닛까지 설치하려면 → sudo ./install_offline.sh --install-service"
    exit 0
}

# 5) systemd 유닛 설치 — .service.example placeholder 치환(계정=SERVICE_USER, 경로=repo 유도).
SERVICE_GROUP="$(id -gn "$SERVICE_USER" 2>/dev/null || echo "$SERVICE_USER")"
# PROJECT_HOME: 표준 레이아웃(~/claude/KooSlurmInstallAutomationRefactory)에서 유도.
PROJECT_HOME="${REPO_ROOT%/claude/KooSlurmInstallAutomationRefactory}"
if [ "$PROJECT_HOME" = "$REPO_ROOT" ]; then
    echo "  ⚠️  repo 가 표준 경로(~/claude/KooSlurmInstallAutomationRefactory)에 없음 → 유닛 경로 수동 확인 필요"
    PROJECT_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
fi
echo "  → PROJECT_HOME=$PROJECT_HOME"

UNIT=/etc/systemd/system/smarttwin-mcp.service
# 주의: 지시어 줄 인라인 주석은 systemd 가 값의 일부로 읽음(→ 217/USER). 템플릿은 주석을 별도 줄로 유지,
#       여기선 placeholder 3종만 치환한다. ('grep -v' 로 줄 삭제 금지 — User= 줄 통째 사라져 root 실행됨.)
sed -e "s|__SERVICE_USER__|$SERVICE_USER|g" \
    -e "s|__SERVICE_GROUP__|$SERVICE_GROUP|g" \
    -e "s|__PROJECT_HOME__|$PROJECT_HOME|g" \
    "$SCRIPT_DIR/smarttwin-mcp.service.example" > "$UNIT"
systemctl daemon-reload
systemctl enable smarttwin-mcp
systemctl restart smarttwin-mcp
sleep 2
systemctl is-active --quiet smarttwin-mcp \
    && echo "[smarttwin_mcp] ✓ 서비스 active — $UNIT" \
    || { echo "[smarttwin_mcp] ✗ 서비스 기동 실패 (journalctl -u smarttwin-mcp -n 20)"; exit 1; }
echo ""
echo "nginx /mcp 컷오버는 cluster/config/nginx_web_production.conf(:5013) 참고 — 폴백 mcp-slurm(:5012) 유지."
