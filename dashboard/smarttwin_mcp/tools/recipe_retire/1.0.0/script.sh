#!/usr/bin/env bash
# recipe_retire — 레시피 판을 내린다(만든 사람만, 이유를 남기고 파일은 지우지 않는다)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity
import recipes

TOOL = "recipe_retire@1.0.0"


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
    user = caller_identity()["username"]
    res = recipes.retire(args.get("name", ""), int(args.get("version", 0)), args.get("reason", ""), user)
    if res.get("retired"):
        audit_event(user, "retire", f"recipe {args.get('name')} v{args.get('version')} retired",
                    f"{args.get('name')}@{args.get('version')}", {"reason": args.get("reason")})
    out({"ok": True, "name": args.get("name"), **res})

try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
