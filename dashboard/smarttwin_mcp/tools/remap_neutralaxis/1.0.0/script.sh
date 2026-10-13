#!/usr/bin/env bash
# remap_neutralaxis — KooRemapper neutralaxis — 적층 단면의 EI 가중 중립축·굽힘강성 계산 (읽기 전용 보고). (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_neutralaxis
