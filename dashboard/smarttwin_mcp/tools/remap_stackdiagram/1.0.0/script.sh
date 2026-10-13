#!/usr/bin/env bash
# remap_stackdiagram — KooRemapper stackdiagram — 파트별 축 범위로 층 모식도를 그리고 중립축·기하 중심면을 함께 긋는다 (포개지는 적층은 거절한다). (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_stackdiagram
