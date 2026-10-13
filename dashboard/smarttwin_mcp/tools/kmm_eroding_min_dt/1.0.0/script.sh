#!/usr/bin/env bash
# kmm_eroding_min_dt — KooMeshModifier ERODING_MIN_DT — 요소 삭제(erosion) 최소 dt 설정 — MAT_ADD_EROSION 류 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_eroding_min_dt
