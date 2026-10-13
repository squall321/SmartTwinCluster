#!/usr/bin/env bash
# kmm_warped_to_initial_stress_part — KooMeshModifier WARPED_TO_INITIAL_STRESS_PART — 워피지를 형상 대신 초기 응력으로 부여 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_warped_to_initial_stress_part
