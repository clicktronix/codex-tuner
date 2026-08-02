#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/codex-tuner/skills/spec/SKILL.md"
RUN="$ROOT/plugins/codex-tuner/skills/run/SKILL.md"
CONFIG="$ROOT/plugins/codex-tuner/assets/execute-task/config.template.md"
CONTRACT="$ROOT/plugins/codex-tuner/workflow-contract.json"
RELEASE_WORKFLOW="$ROOT/.github/workflows/release-please.yml"
failures=0

need() {
  name="$1"; pattern="$2"; file="$3"
  if grep -qF -- "$pattern" "$file"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    failures=1
  fi
}

python3 - "$CONTRACT" <<'PY' \
  && echo "PASS semantic-contract" || { echo "FAIL semantic-contract"; failures=1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["name"] == "clicktronix-development-flow"
assert d["version"] == "1.1.0"
assert d["defaults"]["small_diff"] == {"max_changed_lines": 50, "max_changed_files": 5}
assert d["tracker_values"] == ["gh", "none"]
assert d["delivery_order"] == ["stage", "guard", "commit", "push", "pull_request", "current_sha_ci", "merge", "reconcile"]
assert d["sensitive_surfaces"] == [
    "authentication, authorization, secrets, and cryptography",
    "migrations and destructive data operations",
    "public APIs, persisted schemas, and cross-service contracts",
    "money, payments, pricing, billing, and entitlements",
    "infrastructure, CI, deployment, and release configuration",
    "security-relevant input handling: injection, SSRF, path traversal, unsafe deserialization, and server-side allowlists",
]
ids = [item["id"] for item in d["invariants"]]
assert len(ids) == len(set(ids)) == 14
assert "owned-run-state" in ids
assert "post-merge-reconciliation-only" in ids
assert all(set(item) == {"id", "requirement"} and item["requirement"] for item in d["invariants"])
PY

need "spec-eyes-schema" 'checked by: <human step>; machine replacement: <exact check|none>; waiver: <user/date|none>' "$SPEC"
need "spec-github-tracker" 'tracker: gh|none' "$SPEC"
need "run-loads-contract" '<plugin-root>/workflow-contract.json' "$RUN"
need "run-loads-tiering-reference" '<plugin-root>/references/tiering.md' "$RUN"
need "run-append-command" 'journal.sh" append <literal-run-id>' "$RUN"
need "run-owned-preflight" '--expected-branch <literal-branch>' "$RUN"
need "run-explicit-stage" 'git add -- <path-1> <path-2>' "$RUN"
need "run-explicit-pr-base" 'gh pr create --base <literal-target> --head <literal-branch>' "$RUN"
need "run-current-sha-ci" 'remote head equals the journaled SHA' "$RUN"
need "run-reconciliation-only" 'only board/spec/branch/' "$RUN"
need "release-pr-status" 'context=release-pr/validate' "$RELEASE_WORKFLOW"
need "release-pr-exact-sha" 'ref: ${{ steps.release-pr.outputs.sha }}' "$RELEASE_WORKFLOW"
need "release-pr-runs-suite" 'run: bash tests/run.sh' "$RELEASE_WORKFLOW"
need "release-pr-fails-workflow" '[ "$state" = success ]' "$RELEASE_WORKFLOW"

resume_count="$(grep -cF 'journal.sh" resume <literal-run-id>' "$RUN")"
[ "$resume_count" -eq 8 ] && echo "PASS resume-count" \
  || { echo "FAIL resume-count (got $resume_count, want 8)"; failures=1; }

if rg -n 'glab|effort_tiering|small_diff_budget|assets/tiering|≤50 changed lines|≤5 files' "$SPEC" "$RUN" "$CONFIG" >/dev/null; then
  echo "FAIL ignored-or-duplicated-policy"
  failures=1
else
  echo "PASS no-ignored-or-duplicated-policy"
fi

python3 - "$RUN" <<'PY' \
  && echo "PASS delivery-order" || { echo "FAIL delivery-order"; failures=1; }
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
needles = [
    "git add -- <path-1> <path-2>",
    "guard-artifacts.sh",
    "git commit -m",
    "git push -u origin",
    "gh pr view <literal-branch>",
    "remote head equals the journaled SHA",
    "## Phase 7 — merge and clean up",
    "Confirm the PR is actually `MERGED`",
]
positions = [s.index(value) for value in needles]
assert positions == sorted(positions), positions
PY

exit "$failures"
