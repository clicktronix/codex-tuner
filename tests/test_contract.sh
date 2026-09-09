#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/plugins/codex-tuner"
SPEC="$PLUGIN/skills/spec/SKILL.md"
RUN="$PLUGIN/skills/run/SKILL.md"

require() {
  grep -qF "$2" "$1" || { echo "FAIL missing contract: $2" >&2; exit 1; }
}
reject_tree() {
  if grep -R -n -E "$1" "$PLUGIN" --exclude='*.svg'; then
    echo "FAIL removed runtime residue: $1" >&2
    exit 1
  fi
}

require "$SPEC" 'The implementation outline is guidance for Codex'
require "$SPEC" 'A skill cannot switch the client into Goal mode itself.'
require "$RUN" 'do not create a parallel journal or run-state'
require "$RUN" 'changes at least 15 production files or 500 production lines'
require "$RUN" 'large agent swarm'
require "$RUN" 'Publish every completed external verdict immediately'
require "$RUN" 'Never reset a capped thread to seek an easier verdict.'
require "$RUN" 'At the cap, stop paid review attempts and delivery — not the work.'
require "$RUN" 'they do not
need another confirmation'
require "$RUN" 'merge.sh" --ci <mode>'
require "$RUN" 'unless that authorization was already
given'
require "$RUN" 'reviewed base to be a proper ancestor of the candidate'
require "$RUN" 'delivered as a set'
if grep -qF 'run both typecheck and lint' "$PLUGIN/skills/task-flow/SKILL.md"; then
  echo "FAIL task-flow still prescribes typecheck+lint for every repository" >&2; exit 1
fi
if grep -qF 'use issues without project commands' "$PLUGIN/skills/task-flow/SKILL.md"; then
  echo "FAIL task-flow still conflates tracker: none with board: none" >&2; exit 1
fi
require "$SPEC" 'ci: <mode> — <the checks, and how to observe them>'
require "$SPEC" 'a defined PR per
participating repository'
TASK_FLOW="$PLUGIN/skills/task-flow/SKILL.md"
require "$TASK_FLOW" 'Tracking a defect does not resolve it.'
require "$TASK_FLOW" 'one record for the
class, not one issue per finding'
if grep -qF 'File each deferred review finding as its own issue' "$TASK_FLOW"; then
  echo "FAIL task-flow still files one issue per deferred finding" >&2; exit 1
fi
if grep -qF 'capped review is a hard stop' "$RUN"; then
  echo "FAIL run still treats a capped review as a stop for all work" >&2; exit 1
fi

python3 - "$RUN" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
plan = text.index("Publish a native plan before changing files")
contract = text.index("When no committed spec was supplied")
implementation = text.index("## 2. Implement and prove")
freeze = text.index("## 3. Freeze the candidate")
review = text.index("## 4. Review proportionally")
assert plan < contract < implementation < freeze < review
PY

reject_tree 'runctl\.sh|workflow-contract\.json|run-state\.schema|execute-task-runs|\.agent-state/codex-tuner'
reject_tree 'Phase [0-9]|authoritative run state|Markdown journal'

echo "PASS contract"
