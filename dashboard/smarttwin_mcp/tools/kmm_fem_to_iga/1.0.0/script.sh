#!/usr/bin/env bash
# kmm_fem_to_iga — KooMeshModifier FEM_TO_IGA — FEM 파트를 IGA(NURBS) 파트로 변환 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_fem_to_iga
