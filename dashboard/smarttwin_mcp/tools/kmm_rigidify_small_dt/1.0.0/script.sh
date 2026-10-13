#!/usr/bin/env bash
# kmm_rigidify_small_dt — KooMeshModifier RIGIDIFY_SMALL_DT — stable dt 가 작은 요소를 강체 파트로 분리하고 접촉에서 제외 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_rigidify_small_dt
