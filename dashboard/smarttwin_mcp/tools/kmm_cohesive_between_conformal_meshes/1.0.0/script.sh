#!/usr/bin/env bash
# kmm_cohesive_between_conformal_meshes — KooMeshModifier COHESIVE_BETWEEN_CONFORMAL_MESHES — 절점 공유 두 파트 사이에 코히시브 요소층 삽입 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_cohesive_between_conformal_meshes
