#!/usr/bin/env bash
# kmm_vibration_load — KooMeshModifier VIBRATION_LOAD — 진동 하중 — 하중곡선 × 파트별 계수로 LOAD_BODY/LOAD_NODE 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_vibration_load
