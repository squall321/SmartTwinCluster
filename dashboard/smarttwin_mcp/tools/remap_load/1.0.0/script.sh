#!/usr/bin/env bash
# remap_load — KooRemapper load — YAML으로 부하(압력/힘)를 부분에 적용하고 *LOAD_*, *DEFINE_CURVE, *SET_* 키워드 삽입 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_load
