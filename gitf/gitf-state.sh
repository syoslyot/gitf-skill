#!/usr/bin/env bash
# gitf-state.sh — state access layer for /gitf multi-branch state.
# Store: <worktree-root>/.gitf/state.json, schema v2:
#   {"version":2,"flows":{"<branch>":{...entry...}}}
# Subcommands act on one branch entry at a time. A missing or non-v2 file is
# treated as empty (no entries) — this is the v1->v2 migration path.
set -uo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
STATE_FILE="${GITF_STATE_FILE:-$TOPLEVEL/.gitf/state.json}"

py() {
  GITF_STATE_FILE="$STATE_FILE" python3 - "$@" <<'PYEOF'
import json, sys, os
path = os.environ["GITF_STATE_FILE"]
def load():
    try:
        with open(path) as f:
            d = json.load(f)
        if isinstance(d, dict) and d.get("version") == 2 and isinstance(d.get("flows"), dict):
            return d
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return {"version": 2, "flows": {}}
def save(d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
cmd = sys.argv[1]
d = load()
if cmd == "get":
    e = d["flows"].get(sys.argv[2])
    if e is not None:
        print(json.dumps(e))
elif cmd == "put":
    d["flows"][sys.argv[2]] = json.loads(sys.argv[3])
    save(d)
elif cmd == "del":
    d["flows"].pop(sys.argv[2], None)
    save(d)
elif cmd == "list":
    print(json.dumps(list(d["flows"].keys())))
PYEOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  get)  py get "$1" ;;
  put)  py put "$1" "$2" ;;
  del)  py del "$1" ;;
  list) py list ;;
  valid)
    # valid <branch> <sha> -> exit 0 if sha is an ancestor of branch, else 1
    git merge-base --is-ancestor "$2" "$1" 2>/dev/null ;;
  *)
    echo "usage: gitf-state.sh {get <branch>|put <branch> <json>|del <branch>|list|valid <branch> <sha>}" >&2
    exit 2 ;;
esac
