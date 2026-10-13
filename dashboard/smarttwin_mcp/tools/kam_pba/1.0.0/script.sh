#!/usr/bin/env bash
# kam_pba — KooAutomatedModeller PBA — ODB++ 압축파일(.zip/.tgz)에서 PCB + 부품 실장 보드(PBA) 전체 형상 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kam_pba
