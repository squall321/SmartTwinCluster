#!/usr/bin/env bash
# remap_stackwrap — KooRemapper stackwrap — 적층을 EI 중립축 기준으로 옮겨 기준 셸에 감기 (shellmap 의 z=0 전제를 맞춘다). (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_stackwrap
