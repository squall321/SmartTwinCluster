#!/usr/bin/env bash
# remap_convert — KooRemapper convert — 선형 요소를 2차 요소로 변환 (TET10/HEX20/QUAD8/TRIA6) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_convert
