#!/usr/bin/env bash
# remap_explicit — KooRemapper explicit — LS-DYNA K-file에서 implicit/DR/modal 키워드를 제거하여 순수 explicit 형태로 변환 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_explicit
