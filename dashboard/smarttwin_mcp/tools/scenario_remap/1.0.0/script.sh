#!/usr/bin/env bash
# scenario_remap — KooChainRun REMAP — 누적 스텝 사이에 KooRemapper 변환(재질 교체 등)을 끼우는 러너 전용 스텝 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" scenario_remap
