#!/usr/bin/env bash
# smarttwin_capabilities — 생성기가 만든 기능↔도구 대응표(stmc_specs.json index)를 제품별로 돌려준다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os

args = json.loads(os.environ.get("STMC_ARGS_JSON") or "{}")
with open(os.path.join(os.environ["SHARED_DIR"], "stmc_specs.json"), encoding="utf-8") as f:
    specs = json.load(f)
rows = specs["index"]
if args.get("family"):
    rows = [r for r in rows if r["family"] == args["family"]]
if args.get("query"):
    q = args["query"].lower()
    rows = [r for r in rows if q in " ".join((r["capability"], r["summary"], r["tool"], r["category"])).lower()]
families = {}
for r in rows:
    families.setdefault(r["family"], []).append({k: r[k] for k in ("category", "capability", "tool", "summary")})
print(json.dumps({
    "ok": True, "total": len(rows), "families": families, "sources": specs.get("sources"),
    "how_to": ("catalog_describe(<tool>) 로 인자·사례 → catalog_run(<tool>, args), 계산 도구는 먼저 dry_run=true. "
               "결과: tool_result(job_id) · 캠페인은 job_status·job_collect. "
               "REST: GET /smarttwin-api/v1/tools/<tool> · POST /smarttwin-api/v1/tools/<tool>/run (Bearer PAT)."),
}, ensure_ascii=False))
PY
