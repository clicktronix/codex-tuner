#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$ROOT/plugins/codex-tuner"
SPEC="$PLUGIN/skills/spec/SKILL.md"
RUN="$PLUGIN/skills/run/SKILL.md"

require() {
  grep -qF -- "$2" "$1" || { echo "FAIL missing contract: $2" >&2; exit 1; }
}
reject_tree() {
  if grep -R -n -E "$1" "$PLUGIN" --exclude='*.svg'; then
    echo "FAIL removed runtime residue: $1" >&2
    exit 1
  fi
}

# Verify the public routing schema and reachable commands. Runtime contracts are
# exercised by the merge, receipt and resource suites.
ROUTES="$PLUGIN/skills/run/references/delivery.md"
require "$SPEC" 'host: github|gitlab|local|pending'
require "$SPEC" 'delivery: local|draft|pr|merge'
require "$SPEC" 'review: claude|local'
require "$SPEC" 'ci: <mode>'
# task-flow sends readers here for the CI modes; each name keeps its definition beside it.
require "$SPEC" '- `required`: '
require "$SPEC" '- `any`: '
require "$SPEC" '- `none:<reason>`: '
require "$RUN" '--local-only'
require "$RUN" 'references/delivery.md'
require "$RUN" '../deep-review/SKILL.md'
require "$RUN" '../verify-feature/SKILL.md'
require "$RUN" 'review-state.sh renew'
require "$ROUTES" 'scripts/merge.sh'
require "$ROUTES" 'scripts/local-merge.py'
require "$ROUTES" 'scripts/finish-review.py'
require "$ROUTES" 'glab api "$MR_API/merge"'
require "$RUN" 'scripts/heavy.sh'
require "$PLUGIN/references/resources.md" 'heavy.sh --weight 2'
require "$PLUGIN/references/resources.md" 'heavy.sh: started without a slot'
for file in scripts/check-review.sh scripts/finish-review.py scripts/local-merge.py scripts/destination.py; do
  test -x "$PLUGIN/$file"
done
if grep -Fq -- '--cap 5' "$RUN"; then echo "FAIL delivery overrides the saved reviewer budget" >&2; exit 1; fi

reject_tree 'runctl\.sh|workflow-contract\.json|run-state\.schema|execute-task-runs|\.agent-state/codex-tuner'
reject_tree 'Phase [0-9]|authoritative run state|Markdown journal'
# The spec template has no Definition of Done; acceptance criteria and the verification record carry it.
reject_tree 'DoD|Definition of Done'

echo "PASS contract"
