#!/usr/bin/env bash
# kmm_convert_cnrb_to_solid — KooMeshModifier CONVERT_CNRB_TO_SOLID — 원통 배치 CNRB(나사 등)를 솔리드 원통으로 치환 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_convert_cnrb_to_solid
