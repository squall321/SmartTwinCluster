#!/usr/bin/env bash
# remap_ale — KooRemapper ale — LS-DYNA 파트를 ALE(임의 라그랑-오일러) 형식으로 변환, 물성 프리셋 및 FSI 커플링 적용 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_ale
