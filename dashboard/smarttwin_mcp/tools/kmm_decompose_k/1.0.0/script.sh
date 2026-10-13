#!/usr/bin/env bash
# kmm_decompose_k — KooMeshModifier DECOMPOSE_K — 모델을 그룹별 include 파일 세트로 분해 (master.k + groups/*.k) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_decompose_k
