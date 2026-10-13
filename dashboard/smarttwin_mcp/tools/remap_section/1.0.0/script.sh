#!/usr/bin/env bash
# remap_section — KooRemapper section — 메시를 평면으로 잘라 요소 다각형 + 매니페스트를 낸다 (그림의 엔진). (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_section
