#!/usr/bin/env bash
# recipe_save — 효과를 본 잡을 근거로 도구 인자 틀을 레시피(새 판)로 저장한다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity
import recipes

TOOL = "recipe_save@1.0.0"


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
    recipe = recipes.validate(args.get("recipe"))
    ev = recipes.verify_evidence(recipe, args.get("evidence"), user)
    res = recipes.save(recipe, ev, user)
    if res["saved"]:
        audit_event(user, "save", f"recipe {recipe['name']} v{res['version']} ({recipe['tool']})",
                    f"{recipe['name']}@{res['version']}",
                    {"tool": recipe["tool"], "sha256": res["sha256"], "evidence": ev["result_dir"]})
    out({"ok": True, "name": recipe["name"], "tool": recipe["tool"], **res, "evidence": ev,
         "next": f"recipe_run(name='{recipe['name']}', params={{...}}, model_path 또는 target=...) 로 다시 부른다"})

try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
