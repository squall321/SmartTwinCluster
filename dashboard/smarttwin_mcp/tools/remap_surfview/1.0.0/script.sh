#!/usr/bin/env bash
# remap_surfview — KooRemapper surfview — 자유면만 뽑아 직교투영·깊이정렬로 그린다 (전체 와이어프레임은 검은 덩어리가 된다). (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_surfview
