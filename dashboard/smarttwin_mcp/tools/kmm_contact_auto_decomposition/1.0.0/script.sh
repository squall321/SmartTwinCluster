#!/usr/bin/env bash
# kmm_contact_auto_decomposition — KooMeshModifier CONTACT_AUTO_DECOMPOSITION — 큰 접촉을 근접 파트 쌍 접촉으로 자동 분해 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_contact_auto_decomposition
