#!/usr/bin/env bash
# post_sphere_report — 전각도 낙하 통합 리포트 — Mollweide 구면 지도·방향별 위험도 (또는 --from-json 재생성) (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" post_sphere_report
