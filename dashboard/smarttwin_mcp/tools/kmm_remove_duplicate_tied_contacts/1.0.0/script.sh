#!/usr/bin/env bash
# kmm_remove_duplicate_tied_contacts — KooMeshModifier REMOVE_DUPLICATE_TIED_CONTACTS — 같은 면을 중복으로 묶은 TIED 접촉 제거 (생성됨: tools/_gen/generate_smarttwin_tools.py)
# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).
set -euo pipefail
SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
exec python3 "$SHARED_DIR/stmc_tools.py" kmm_remove_duplicate_tied_contacts
