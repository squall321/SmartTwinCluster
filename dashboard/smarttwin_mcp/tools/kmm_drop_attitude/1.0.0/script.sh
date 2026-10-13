#!/usr/bin/env bash
# kmm_drop_attitude — KooMeshModifier DROP_ATTITUDE — 제품 낙하 해석 덱 생성 — 자세(오일러각)·높이·바닥판·접촉 자동 구성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_drop_attitude
