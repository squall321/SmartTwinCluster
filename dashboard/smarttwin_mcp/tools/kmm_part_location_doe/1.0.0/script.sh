#!/usr/bin/env bash
# kmm_part_location_doe — KooMeshModifier PART_LOCATION_DOE — 파트 배치 DOE — 마스크 파트 안 격자/샘플 위치에 파트 배치 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_part_location_doe
