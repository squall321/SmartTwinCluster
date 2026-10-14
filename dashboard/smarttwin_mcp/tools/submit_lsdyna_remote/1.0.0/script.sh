#!/usr/bin/env bash
# submit_lsdyna_remote@1.0.0 — 보안 수정(2026-10-14)으로 1.1.0 버전을 그대로 실행한다(인자 스키마 동일).
# 예전 스크립트는 backend 권한·감사를 건너뛰거나 경로를 검사 없이 썼다. 감사(audit.record_event)는 위임한 스크립트가 남긴다.
set -euo pipefail
exec "$(dirname "$0")/../1.1.0/script.sh"
