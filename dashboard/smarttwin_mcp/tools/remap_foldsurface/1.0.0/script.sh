#!/usr/bin/env bash
# remap_foldsurface — KooRemapper foldsurface — 접힘 곡면(평면 elastica) 중심선 — 최소 곡률반경을 목표로 고정하고 B 를 푼다. (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_foldsurface
