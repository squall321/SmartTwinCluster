#!/usr/bin/env bash
# recipe_get — 레시피 한 판의 전체(매개변수·인자 틀·근거·상태)를 본다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity
import recipes

TOOL = "recipe_get@1.0.0"


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
    out({"ok": True, "recipe": recipes.load(args.get("name", ""), args.get("version"))})

try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
