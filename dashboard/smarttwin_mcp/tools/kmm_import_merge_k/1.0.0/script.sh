#!/usr/bin/env bash
# kmm_import_merge_k — KooMeshModifier IMPORT_MERGE_K — 다른 .k 파일을 불러와 ID 충돌 없이 현재 모델에 합침 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_import_merge_k
