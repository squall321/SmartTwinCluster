#!/usr/bin/env bash
# post_custom_report — *SET_ 정의 기반 커스텀 후처리 리포트 — 세트별 응력·변형률·영상 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" post_custom_report
