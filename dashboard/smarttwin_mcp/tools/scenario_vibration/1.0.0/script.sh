#!/usr/bin/env bash
# scenario_vibration — KooChainRun VIBRATION — 진동 시나리오 — 하중 곡선 × 파트 계수 (명시·캡별·회로별 DOE) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" scenario_vibration
