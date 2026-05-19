#!/bin/bash
################################################################################
# 핵심 build dependencies (wheel, setuptools, pip, Cython) 을 기존
# python_wheels/python3.X/ 에 추가 다운로드 (인터넷 가능한 PC에서 실행)
#
# 사용:
#   ./add_build_deps.sh           # 3.12 + 3.13 모두
#   ./add_build_deps.sh 3.13      # 특정 버전만
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

VERSIONS=("$@")
[ ${#VERSIONS[@]} -eq 0 ] && VERSIONS=(3.12 3.13)

CORE_PKGS=(wheel setuptools pip Cython)

for ver in "${VERSIONS[@]}"; do
    py_cmd="python${ver}"
    if ! command -v "$py_cmd" &>/dev/null; then
        echo -e "${YELLOW}⚠️  $py_cmd 없음, 스킵${NC}"; continue
    fi
    target="${SCRIPT_DIR}/python_wheels/python${ver}"
    mkdir -p "$target"
    echo -e "${GREEN}→ Python $ver: ${CORE_PKGS[*]} → $target${NC}"
    "$py_cmd" -m pip download "${CORE_PKGS[@]}" \
        --dest "$target" \
        --prefer-binary 2>&1 | tail -5 || \
        echo -e "${RED}❌ 일부 실패${NC}"
done

# 부모 dir 에도 사본 복사 (--find-links 둘 다 검색용)
for ver in "${VERSIONS[@]}"; do
    src="${SCRIPT_DIR}/python_wheels/python${ver}"
    [ -d "$src" ] || continue
    for f in "$src"/wheel*.whl "$src"/setuptools*.whl "$src"/pip*.whl "$src"/Cython*.whl; do
        [ -f "$f" ] && cp -n "$f" "${SCRIPT_DIR}/python_wheels/" 2>/dev/null || true
    done
done

echo -e "${GREEN}✅ 완료${NC}"
ls -la "${SCRIPT_DIR}/python_wheels/python3.12/" 2>/dev/null | grep -iE "wheel|setuptools|pip|cython" | head
ls -la "${SCRIPT_DIR}/python_wheels/python3.13/" 2>/dev/null | grep -iE "wheel|setuptools|pip|cython" | head
