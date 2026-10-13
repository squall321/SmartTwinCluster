#!/usr/bin/env bash
# scenario_drop_weight_impact — KooChainRun drop_weight_impact — (구) 전위치 부분충격 워크플로우 — IMPACT 시나리오와 별도 스키마 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" scenario_drop_weight_impact
