#!/usr/bin/env bash
# kmm_rigid_drop_endtime — KooMeshModifier RIGID_DROP_ENDTIME — 강체 낙하 사전 해석 — 질량특성·외곽면(OBJ)·볼록 껍질로 각도별 종료 시간(ENDTIM) 표를 만든다 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_rigid_drop_endtime
