#!/usr/bin/env bash
# scenario_part_validation — KooChainRun part_validation — 파트별 0° 낙하 검증 — 파트마다 독립 .k 로 쪼개 해석 가능 여부 사전 점검 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" scenario_part_validation
