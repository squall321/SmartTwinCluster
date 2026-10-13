#!/usr/bin/env bash
# scenario_impact — KooChainRun IMPACT — 충격 시나리오 — 모델 윗면 격자 위치마다 구·다단 실린더 충격추 낙하 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" scenario_impact
