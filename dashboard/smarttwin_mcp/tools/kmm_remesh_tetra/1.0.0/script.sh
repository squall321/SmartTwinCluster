#!/usr/bin/env bash
# kmm_remesh_tetra — KooMeshModifier REMESH_TETRA — 지정 파트를 품질 좋은 사면체로 재메시 (공유 절점 유지) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_remesh_tetra
