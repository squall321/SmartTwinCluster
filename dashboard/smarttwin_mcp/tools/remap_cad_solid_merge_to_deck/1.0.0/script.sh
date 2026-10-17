#!/usr/bin/env bash
# remap_cad_solid_merge_to_deck — KooRemapper cad_solid_merge_to_deck — Insert a StepForge part fragment (.k + map JSON) into an existing deck: check it against the boundary contract, keep its numbers when they lie (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_cad_solid_merge_to_deck
