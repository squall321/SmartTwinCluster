#!/usr/bin/env bash
# kmm_weak_coupling — KooMeshModifier WEAK_COUPLING — 전체 모델 결과(d3plot) 경계 변위로 부분 모델 구동 (서브모델링) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_weak_coupling
