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
require "$RUN" 'merge.sh'

reject_tree 'runctl\.sh|workflow-contract\.json|run-state\.schema|execute-task-runs|\.agent-state/codex-tuner'
reject_tree 'Phase [0-9]|authoritative run state|Markdown journal'

echo "PASS contract"
