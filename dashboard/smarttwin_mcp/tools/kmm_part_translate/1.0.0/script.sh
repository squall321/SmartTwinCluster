#!/usr/bin/env bash
# kmm_part_translate — KooMeshModifier PART_TRANSLATE — 특정 파트만 이동 (이동 유지 — 뒤 모드가 이동된 형상 사용) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_part_translate
