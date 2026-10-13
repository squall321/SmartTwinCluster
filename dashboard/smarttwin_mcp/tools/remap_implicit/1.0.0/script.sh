#!/usr/bin/env bash
# remap_implicit — KooRemapper implicit — LS-DYNA explicit K-file을 implicit 솔버 세팅으로 변환하며, 명시적 전용 카드 제거 및 CONTROL_IMPLICIT_* 블록 삽입 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_implicit
