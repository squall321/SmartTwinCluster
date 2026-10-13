#!/usr/bin/env bash
# kmm_translation_doe — KooMeshModifier TRANSLATION_DOE — 파트 위치 DOE — 파트별 이동량 목록마다 .k 한 개씩 (원복) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_translation_doe
