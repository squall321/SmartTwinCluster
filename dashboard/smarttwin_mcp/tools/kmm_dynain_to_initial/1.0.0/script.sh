#!/usr/bin/env bash
# kmm_dynain_to_initial — KooMeshModifier DYNAIN_TO_INITIAL — 이전 해석 dynain(변형 형상+응력)을 다음 해석 초기 상태로 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_dynain_to_initial
