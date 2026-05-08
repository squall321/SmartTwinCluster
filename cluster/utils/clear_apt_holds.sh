#!/bin/bash
################################################################################
# 모든 apt-mark hold 해제 — 사고 복구용
#
# 증상: "pkgProblemResolver::Resolve generated breaks, this may be caused by held packages"
# 원인: phase3_slurm.sh가 도중 실패하여 hold 상태로 영구히 남은 경우
#
# 사용:
#   sudo bash cluster/utils/clear_apt_holds.sh
################################################################################

set -uo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: root 필요 (sudo)"; exit 1; }

held=$(apt-mark showhold 2>/dev/null)
if [[ -z "$held" ]]; then
    echo "현재 hold된 패키지 없음"
    exit 0
fi

echo "현재 hold된 패키지:"
echo "$held" | sed 's/^/  /'
echo ""
echo "모두 hold 해제 중..."
for pkg in $held; do
    apt-mark unhold "$pkg" 2>/dev/null && echo "  unhold: $pkg"
done

echo ""
echo "완료. 이제 apt-get update / install 정상 동작:"
echo "  sudo apt-get update"
echo "  sudo apt-get -f install"
