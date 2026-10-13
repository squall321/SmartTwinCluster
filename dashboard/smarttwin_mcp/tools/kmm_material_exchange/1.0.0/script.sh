#!/usr/bin/env bash
# kmm_material_exchange — KooMeshModifier MATERIAL_EXCHANGE — 재료 카드 치환 + 변수 스윕 — 값 목록마다 .k 한 개씩 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_material_exchange
