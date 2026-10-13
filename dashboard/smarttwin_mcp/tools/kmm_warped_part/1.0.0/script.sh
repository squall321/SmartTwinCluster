#!/usr/bin/env bash
# kmm_warped_part — KooMeshModifier WARPED_PART — 워피지(휨) 측정 데이터를 파트 형상에 반영 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_warped_part
