#!/usr/bin/env bash
# kam_pkg — KooAutomatedModeller PKG — 적층(Layer) 정의 텍스트로 반도체 패키지 형상(STEP) 또는 LS-DYNA 메시(.k) 생성 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kam_pkg
