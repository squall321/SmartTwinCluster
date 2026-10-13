#!/usr/bin/env bash
# kmm_part_exchange — KooMeshModifier PART_EXCHANGE — 파트의 재료·단면·요소 형식 교체 (솔리드→TShell, 비정렬→정렬 격자 등) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_part_exchange
