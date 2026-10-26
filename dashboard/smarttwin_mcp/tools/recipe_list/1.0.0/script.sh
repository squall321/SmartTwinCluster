#!/usr/bin/env bash
# recipe_list — 레시피 등록소에서 쓸 수 있는 레시피를 찾는다(이름·요약·태그·대상 도구)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity
import recipes

TOOL = "recipe_list@1.0.0"


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
    rows = recipes.list_all(args.get("query"), args.get("tool"), bool(args.get("include_retired", False)))
    out({"ok": True, "count": len(rows), "recipes": rows,
         "hint": "recipe_get 으로 전체(인자 틀·근거)를 보고 recipe_run 으로 부른다. 없으면 kmm_chain·post_* 로 해 보고 효과가 있으면 recipe_save."})

try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
