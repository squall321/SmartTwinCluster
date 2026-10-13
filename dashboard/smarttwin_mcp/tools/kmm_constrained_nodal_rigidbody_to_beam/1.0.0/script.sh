#!/usr/bin/env bash
# kmm_constrained_nodal_rigidbody_to_beam — KooMeshModifier CONSTRAINED_NODAL_RIGIDBODY_TO_BEAM — CNRB(절점 강체) 연결을 빔 요소로 치환 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_constrained_nodal_rigidbody_to_beam
