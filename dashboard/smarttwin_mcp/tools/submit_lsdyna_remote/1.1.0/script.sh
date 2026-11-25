#!/usr/bin/env bash
# submit_lsdyna_remote@1.1.0 — 닫힘(SM-01, 2026-11-25): 원격 헤드에서 ssh 로 돌아 호출자(PAT)를 확인할 수 없다.
# 예전 스크립트는 서비스 계정 명의로 sbatch 를 냈다(git 이력에 있다). 같은 일은 submit_lsdyna_job(backend 경유)으로 한다.
set -euo pipefail
echo '{"ok": false, "reason": "submit_lsdyna_remote 는 닫혔다(SM-01) — 호출자(PAT)를 확인할 수 없는 원격 sbatch 다. 같은 헤드의 submit_lsdyna_job 을 쓸 것."}'
exit 1
