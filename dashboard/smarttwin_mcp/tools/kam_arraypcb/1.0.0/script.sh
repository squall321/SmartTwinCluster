#!/usr/bin/env bash
# kam_arraypcb — KooAutomatedModeller ArrayPCB — 어레이(판넬) PCB 형상 생성 — *PCB 와 같은 키, 워피지 파일 지원 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kam_arraypcb
