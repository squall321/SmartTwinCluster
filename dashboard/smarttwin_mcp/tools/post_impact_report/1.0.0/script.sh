#!/usr/bin/env bash
# post_impact_report — 부분충격(DWI) 다면 DOE 리포트 — 면별 위치 격자 위험도 (또는 --from-json 재생성) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" post_impact_report
