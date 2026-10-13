#!/usr/bin/env bash
# kmm_thermal_load — KooMeshModifier THERMAL_LOAD — 열 하중 — 균일 온도 변화 열응력 또는 IC 발열(ICPower) 2-pass (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_thermal_load
