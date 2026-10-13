#!/usr/bin/env bash
# remap_extract_parts — KooRemapper extract-parts — Write a deck holding only the chosen parts, keeping every ID, the deck's field width and its newlines, then read it back and report any missing referenc (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_extract_parts
