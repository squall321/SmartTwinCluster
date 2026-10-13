#!/usr/bin/env bash
# post_dyna_diag — LS-DYNA 결과 진단 — 에러·경고·성능 프로파일 JSON/HTML (단일 폴더 또는 일괄 색인) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" post_dyna_diag
