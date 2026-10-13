#!/usr/bin/env bash
# mcp_slurm 오프라인 설치 — 인터넷 없는 운영서에서 MCP 서버 의존성(mcp SDK)을
# repo 동봉 wheel 로 설치한다. (offline_packages 패턴, --no-index)
#
# 사용:
#   ./install_offline.sh [VENV_DIR]
#   VENV_DIR 미지정 시 ./venv 생성.
#
# 파이썬 버전/OS 자동 감지:
#   - Ubuntu 22.04 (python3.10) → offline_packages/python_wheels/mcp/python3.10
#   - Ubuntu 24.04 (python3.12) → offline_packages_2404/python_wheels/mcp/python3.12
#   - 그 외/3.12 → offline_packages/python_wheels/mcp/python3.12 폴백
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="${1:-$SCRIPT_DIR/venv}"

# 1) 파이썬 인터프리터 결정 (3.12 우선, 없으면 3.10, 없으면 python3)
PYBIN=""
for cand in python3.12 python3.10 python3; do
    if command -v "$cand" >/dev/null 2>&1; then PYBIN="$cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "ERROR: python3 을 찾을 수 없습니다."; exit 1; }
PY_MM="$("$PYBIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
echo "[mcp_slurm] 파이썬: $PYBIN ($PY_MM)"

# 2) wheel 디렉토리 결정 (OS/버전별). 존재하는 첫 후보 사용.
CANDIDATES=(
    "$REPO_ROOT/offline_packages_2404/python_wheels/mcp/python${PY_MM}"
    "$REPO_ROOT/offline_packages/python_wheels/mcp/python${PY_MM}"
    "$REPO_ROOT/offline_packages/python_wheels/mcp/python3.12"
)
WHEELDIR=""
for d in "${CANDIDATES[@]}"; do
    if [ -d "$d" ] && ls "$d"/*.whl >/dev/null 2>&1; then WHEELDIR="$d"; break; fi
done
[ -n "$WHEELDIR" ] || { echo "ERROR: mcp wheel 디렉토리를 찾을 수 없습니다 (python${PY_MM}). 후보: ${CANDIDATES[*]}"; exit 1; }
echo "[mcp_slurm] wheel: $WHEELDIR ($(ls "$WHEELDIR"/*.whl | wc -l) 개)"

# 3) venv 생성 + 오프라인 설치 (--no-index = 인터넷 미사용)
[ -d "$VENV_DIR" ] || "$PYBIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --no-index --find-links="$WHEELDIR" "mcp>=1.2.0,<2.0.0" \
    && echo "[mcp_slurm] ✓ 설치 완료: $VENV_DIR" \
    || { echo "[mcp_slurm] ✗ 설치 실패"; exit 1; }

# 4) 검증
"$VENV_DIR/bin/python" -c "from mcp.server.fastmcp import FastMCP; print('[mcp_slurm] ✓ FastMCP import OK')" \
    || { echo "[mcp_slurm] ✗ import 검증 실패"; exit 1; }

echo ""
echo "다음: 이 venv 파이썬으로 server.py 를 실행하도록 .mcp.json 의 command 를 설정하세요:"
echo "  \"command\": \"$VENV_DIR/bin/python\","
echo "  \"args\": [\"$SCRIPT_DIR/server.py\"]"
