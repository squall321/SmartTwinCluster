#!/usr/bin/env bash
# kam_capacitor — KooAutomatedModeller CAPACITOR — MLCC 칩 커패시터(패드·터미널·솔더·유전체 적층) 형상과 메시 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kam_capacitor
