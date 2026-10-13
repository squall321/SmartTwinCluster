#!/usr/bin/env bash
# kmm_drop_weight_impact_test — KooMeshModifier DROP_WEIGHT_IMPACT_TEST — 낙추(충격추) 시험 덱 — 구·다단 실린더 충격추를 모델 위 지점에 떨어뜨림 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_drop_weight_impact_test
