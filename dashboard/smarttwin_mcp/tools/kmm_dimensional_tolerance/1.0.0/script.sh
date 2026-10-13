#!/usr/bin/env bash
# kmm_dimensional_tolerance — KooMeshModifier DIMENSIONAL_TOLERANCE — 파트 치수 공차 DOE — 목록/정규분포/LHS 로 파트 크기 변형 케이스 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_dimensional_tolerance
