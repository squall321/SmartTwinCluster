#!/usr/bin/env bash
# kmm_part_validation_split — KooMeshModifier PART_VALIDATION_SPLIT — 파트별 독립 .k 분할 + 0° 낙하 검증 모델 일괄 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_part_validation_split
