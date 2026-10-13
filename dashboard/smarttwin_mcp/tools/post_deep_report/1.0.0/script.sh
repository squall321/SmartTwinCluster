#!/usr/bin/env bash
# post_deep_report — 단일 시뮬 깊은 분석 HTML 리포트 — 파트별 응력·변형률·핫스팟 군집·단면뷰 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" post_deep_report
