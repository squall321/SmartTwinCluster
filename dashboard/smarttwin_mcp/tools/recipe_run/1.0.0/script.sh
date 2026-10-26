#!/usr/bin/env bash
# recipe_run — 레시피를 매개변수로 펼쳐 원래 도구(kmm_*·kmm_chain·post_*)로 제출한다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity
import recipes

TOOL = "recipe_run@1.0.0"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def audit_event(user, action, summary, target, detail):
    try:
        import audit
        audit.record_event(actor=user, tool=TOOL, action=action, summary=summary,
                           target_kind="recipe", target_id=target, detail=detail)
    except Exception:  # noqa: BLE001 — 감사 실패가 도구를 막지 않는다
        pass

def main(args):
    rec = recipes.load(args.get("name", ""), args.get("version"))
    runtime = {k: args.get(k) for k in recipes.RUNTIME_KEYS}
    run_args = recipes.run_args(rec, args.get("params"), runtime)
    import stmc_tools
    spec = stmc_tools._specs()["tools"][rec["tool"]]
    res = stmc_tools.RUNNERS[spec["family"]](rec["tool"], spec, run_args)
    info = {"name": rec["name"], "version": rec["version"], "sha256": rec.get("sha256"), "status": rec.get("status")}
    if rec.get("status") != "active":
        info["warning"] = f"내려진 판이다({rec.get('retired_reason', '')}) — 옛 결과를 다시 볼 때만 쓸 것"
    if res.get("ok") and not res.get("dry_run"):
        audit_event(caller_identity()["username"], "run", f"recipe {rec['name']} v{rec['version']} -> {rec['tool']}",
                    f"{rec['name']}@{rec['version']}", {"job": res.get("job_id"), "registry_id": res.get("registry_id")})
    out({**res, "recipe": info}, 0 if res.get("ok") else 1)

try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
