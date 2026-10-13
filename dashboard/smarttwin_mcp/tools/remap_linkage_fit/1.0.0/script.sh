#!/usr/bin/env bash
# remap_linkage_fit — KooRemapper linkage-fit — 접힌 덱에서 군별 강체변환(축·각·피벗·축이동) 역산 — 피벗 산포를 함께 보고. (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_linkage_fit
