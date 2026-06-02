#!/bin/bash
################################################################################
# 누락된 wheel 패키지만 보충 다운로드 (VM 안에서 실행)
#
# 사용처:
#   - 운영 헤드 (오프라인) 에서 install 시 "No matching distribution" 뜬 패키지
#   - 인터넷 되는 VM (Ubuntu 24.04, Python 3.12 + 3.13 설치) 으로 옮겨와서 실행
#
# 사용법:
#   # VM 안에서
#   ./add_missing_wheels.sh                     # 미리 정의된 누락 패키지 다운로드
#   ./add_missing_wheels.sh Nuitka==2.7.12 ...  # 임의 패키지 지정
#
# 출력:
#   /tmp/missing_wheels/python3.12/*.whl
#   /tmp/missing_wheels/python3.13/*.whl
#
# 그 후:
#   - /tmp/missing_wheels/python3.{12,13}/*.whl 을 헤드의
#     offline_packages_2404/python_wheels/python3.{12,13}/ 로 복사
#   - 또는 push-to-drive.sh --incremental 로 Drive 업로드 후 헤드 pull
################################################################################

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# 기본 누락 목록 (인자 없으면 이거)
DEFAULT_PACKAGES=(
    "Nuitka==2.7.12"
    # 필요 시 추가:
    # "wheel==0.47.0"
    # "setuptools==82.0.1"
)

OUTPUT_BASE="${OUTPUT_BASE:-/tmp/missing_wheels}"

# 인자로 패키지 받으면 그거 사용
if [[ $# -gt 0 ]]; then
    PACKAGES=("$@")
else
    PACKAGES=("${DEFAULT_PACKAGES[@]}")
fi

echo -e "${YELLOW}=== 누락 wheel 다운로드 ===${NC}"
echo "대상 패키지: ${PACKAGES[*]}"
echo "출력 위치:   $OUTPUT_BASE"
echo ""

# Python 버전별 다운로드
for py_ver in 3.12 3.13; do
    py_cmd="python${py_ver}"
    if ! command -v "$py_cmd" &>/dev/null; then
        echo -e "${YELLOW}⚠ $py_cmd 없음 — 스킵${NC}"
        continue
    fi

    out_dir="${OUTPUT_BASE}/python${py_ver}"
    mkdir -p "$out_dir"

    echo -e "${GREEN}→ Python ${py_ver} 용 다운로드 (binary only)${NC}"
    for pkg in "${PACKAGES[@]}"; do
        echo "  $pkg"
        "$py_cmd" -m pip download "$pkg" \
            --only-binary=:all: \
            --python-version "${py_ver}" \
            --platform manylinux2014_x86_64 \
            --platform manylinux_2_17_x86_64 \
            --platform manylinux_2_28_x86_64 \
            --platform any \
            -d "$out_dir" 2>&1 | tail -3 | sed 's/^/    /' || {
            echo -e "    ${YELLOW}⚠ binary 없음 — sdist 시도${NC}"
            "$py_cmd" -m pip download "$pkg" \
                --no-deps \
                -d "$out_dir" 2>&1 | tail -3 | sed 's/^/    /' || \
                echo -e "    ${RED}❌ 실패${NC}"
        }
    done

    echo ""
    echo -e "${GREEN}✓ ${out_dir} 결과:${NC}"
    ls -lh "$out_dir" 2>/dev/null | tail -n +2 | head -10
    echo ""
done

echo ""
echo -e "${GREEN}=== 완료 ===${NC}"
echo ""
echo "다음 단계 (헤드에서):"
echo "  scp -r vm:${OUTPUT_BASE}/python3.12/*.whl  offline_packages_2404/python_wheels/python3.12/"
echo "  scp -r vm:${OUTPUT_BASE}/python3.13/*.whl  offline_packages_2404/python_wheels/python3.13/"
echo ""
echo "또는 Drive 경유:"
echo "  VM:   ./offline_packages_2404/push-to-drive.sh --incremental --note 'add-missing-wheels'"
echo "  헤드: ./offline_packages_2404/pull-from-drive.sh"
