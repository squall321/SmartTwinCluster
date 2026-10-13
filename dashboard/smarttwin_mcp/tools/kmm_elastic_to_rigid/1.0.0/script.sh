#!/usr/bin/env bash
# kmm_elastic_to_rigid — KooMeshModifier ELASTIC_TO_RIGID — 모든 변형체 파트를 강체(MAT_RIGID)로 — 지정 PID 만 제외 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_elastic_to_rigid
