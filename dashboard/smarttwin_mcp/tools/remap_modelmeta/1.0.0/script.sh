#!/usr/bin/env bash
# remap_modelmeta — KooRemapper modelmeta — Extract structured model metadata JSON — per-part free-surface area, volume, x/y/z projected areas, material (K-file card + bundled DB), and part-to-part co (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" remap_modelmeta
