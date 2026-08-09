#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/codex-tuner/skills/spec/SKILL.md"
RUN="$ROOT/plugins/codex-tuner/skills/run/SKILL.md"
README="$ROOT/README.md"
PREREQ="$ROOT/plugins/codex-tuner/scripts/execute-task/prereq-check.sh"
CONFIG="$ROOT/plugins/codex-tuner/assets/execute-task/config.template.md"
CONTRACT="$ROOT/plugins/codex-tuner/workflow-contract.json"
RUN_STATE_SCHEMA="$ROOT/plugins/codex-tuner/schemas/run-state.schema.json"
RELEASE_WORKFLOW="$ROOT/.github/workflows/release-please.yml"
VALIDATE_WORKFLOW="$ROOT/.github/workflows/validate.yml"
# Keep this value identical to cc-tuner and update it only in coordinated contract PRs.
EXPECTED_SHARED_CONTRACT_SHA256="5d1a50de037c5f2f850869a0ea1b86932b702d83452995e8a5e3f8f27abdb4e5"
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

release_action_is_current() {
  ruby -ryaml - "$1" <<'RB'
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
steps = workflow.fetch("jobs").fetch("release-please").fetch("steps")
release_step = steps.find { |step| step["id"] == "release" }
abort unless release_step&.fetch("uses", nil) == "googleapis/release-please-action@v5"
RB
}

contract_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    return 1
  fi
}

actual_contract_sha256="$(contract_sha256 "$CONTRACT")"
[ "$actual_contract_sha256" = "$EXPECTED_SHARED_CONTRACT_SHA256" ] \
  && echo "PASS shared-contract-fingerprint" \
  || { echo "FAIL shared-contract-fingerprint"; failures=1; }

python3 - "$RUN_STATE_SCHEMA" <<'PY' \
  && echo "PASS run-state-schema-identity" || { echo "FAIL run-state-schema-identity"; failures=1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["$id"] == "https://github.com/clicktronix/codex-tuner/schemas/run-state.schema.json"
assert d["title"] == "codex-tuner run state"
assert "codex-tuner run lifecycle" in d["description"]
assert "cc-tuner" not in d["description"]
PY

python3 - "$CONTRACT" <<'PY' \
  && echo "PASS semantic-contract" || { echo "FAIL semantic-contract"; failures=1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["name"] == "clicktronix-development-flow"
assert d["version"] == "2.0.0"
assert d["defaults"]["small_diff"] == {"max_changed_lines": 50, "max_changed_files": 5}
assert d["tracker_values"] == ["gh", "none"]
assert d["lifecycle_order"] == ["readiness", "planning", "implementation", "testing", "acceptance", "candidate", "review", "delivery", "completion"]
assert d["delivery_order"] == ["stage", "guard", "commit_candidate", "review_candidate", "push", "pull_request", "current_sha_ci", "definition_of_done", "merge", "reconcile"]
assert d["review_lenses"] == [
    "correctness and edge cases",
    "specification and scope",
    "repository standards",
    "architecture and systemic effects",
    "security and data safety",
    "tests and operability",
]
assert d["sensitive_surfaces"] == [
    "authentication, authorization, secrets, and cryptography",
    "migrations and destructive data operations",
    "public APIs, persisted schemas, and cross-service contracts",
    "money, payments, pricing, billing, and entitlements",
    "infrastructure, CI, deployment, and release configuration",
    "security-relevant input handling: injection, SSRF, path traversal, unsafe deserialization, and server-side allowlists",
]
ids = [item["id"] for item in d["invariants"]]
assert len(ids) == len(set(ids)) == 24
assert "structured-run-state" in ids
assert "visible-plan-before-mutation" in ids
assert "immutable-candidate-before-review" in ids
assert "changes-invalidate-downstream-evidence" in ids
assert "definition-of-done-before-merge" in ids
assert "post-merge-reconciliation-only" in ids
assert all(set(item) == {"id", "requirement"} and item["requirement"] for item in d["invariants"])
PY

need "spec-eyes-schema" 'checked by: <human step>; machine replacement: <exact check|none>; waiver: <user/date|none>' "$SPEC"
need "spec-github-tracker" 'tracker: gh|none' "$SPEC"
need "spec-prereq-check" 'scripts/execute-task/prereq-check.sh' "$SPEC"
need "spec-grilling" 'Invoke `$grilling` before drafting.' "$SPEC"
need "spec-domain-modeling" 'Invoke `$domain-modeling` when the task changes domain vocabulary' "$SPEC"
need "matt-codex-install" 'npx skills@latest add mattpocock/skills --global --agent codex --skill grilling domain-modeling code-review --yes' "$README"
need "matt-codex-install-hint" 'npx skills@latest add mattpocock/skills --global --agent codex --skill grilling domain-modeling code-review --yes' "$PREREQ"
need "run-loads-contract" '`workflow-contract.json`' "$RUN"
need "run-loads-tiering-reference" '`references/tiering.md`' "$RUN"
need "run-structured-state" 'runctl.sh` is authoritative' "$RUN"
need "run-exact-phase-completion" 'phase <literal-run-id> complete <literal-phase>' "$RUN"
need "run-append-command" 'journal.sh" append <literal-run-id>' "$RUN"
need "run-owned-preflight" '--expected-branch <literal-branch>' "$RUN"
need "run-explicit-stage" 'git add -- <path-1> <path-2>' "$RUN"
need "run-explicit-pr-create" 'gh pr create --base <literal-target> --head <literal-branch> --title "<literal-title>"' "$RUN"
need "run-current-sha-ci" 'record success <candidate-sha> --pr <literal-pr-number>' "$RUN"
need "run-reconciliation" '<literal merged PR, issue/board, spec/archive, and cleanup evidence>' "$RUN"
need "run-prereq-check" 'scripts/execute-task/prereq-check.sh' "$RUN"
need "run-claude-review" '$codex-cc-triage:claude-review --required --base <literal-base-sha>' "$RUN"
need "run-claude-marker" 'CODEX_CC_REQUIRED_REVIEW APPROVE' "$RUN"
need "run-matt-review" 'Invoke `$code-review` with the fixed base' "$RUN"
need "run-visible-plan" '`update_plan` with:' "$RUN"
need "run-implementation-only-parallel" 'Parallelize only independent code-writing units' "$RUN"
need "run-testing-phase" '## Phase 3 — Testing & Code Verification' "$RUN"
need "run-atomic-merge-head" '--match-head-commit <literal-candidate-sha>' "$RUN"
need "release-pr-status" 'context=release-pr/validate' "$RELEASE_WORKFLOW"
need "release-pr-exact-sha" 'ref: ${{ steps.release-pr.outputs.sha }}' "$RELEASE_WORKFLOW"
need "release-pr-runs-suite" 'run: bash tests/run.sh' "$RELEASE_WORKFLOW"
need "release-pr-fails-workflow" '[ "$state" = success ]' "$RELEASE_WORKFLOW"
need "release-pr-create-update-gate" 'sets prs_created when a release PR is created or updated' "$RELEASE_WORKFLOW"
need "release-checkout-current" 'uses: actions/checkout@v7' "$RELEASE_WORKFLOW"
need "validate-checkout-current" 'uses: actions/checkout@v7' "$VALIDATE_WORKFLOW"
release_action_is_current "$RELEASE_WORKFLOW" \
  && echo "PASS release-action-node24" \
  || { echo "FAIL release-action-node24"; failures=1; }

release_mutation="$(mktemp)"
trap 'rm -f "$release_mutation"' EXIT
sed 's|uses: googleapis/release-please-action@v5|uses: googleapis/release-please-action@v4|' \
  "$RELEASE_WORKFLOW" > "$release_mutation"
if release_action_is_current "$release_mutation" 2>/dev/null; then
  echo "FAIL release-action-node24-mutation"
  failures=1
else
  echo "PASS release-action-node24-mutation"
fi

release_pr_gate_count="$(grep -cF "steps.release.outputs.prs_created == 'true'" "$RELEASE_WORKFLOW")"
[ "$release_pr_gate_count" -eq 4 ] && echo "PASS release-pr-gate-count" \
  || { echo "FAIL release-pr-gate-count (got $release_pr_gate_count, want 4)"; failures=1; }

phase_count="$(grep -cE '^## Phase [0-8] —' "$RUN")"
[ "$phase_count" -eq 9 ] && echo "PASS phase-count" \
  || { echo "FAIL phase-count (got $phase_count, want 9)"; failures=1; }

if grep -En 'glab|effort_tiering|small_diff_budget|assets/tiering|≤50 changed lines|≤5 files' "$SPEC" "$RUN" "$CONFIG" >/dev/null; then
  echo "FAIL ignored-or-duplicated-policy"
  failures=1
else
  echo "PASS no-ignored-or-duplicated-policy"
fi

if grep -REn 'mattpocock/mattpocock-skills' "$ROOT/README.md" "$ROOT/plugins" >/dev/null; then
  echo "FAIL stale-mattpocock-repository"
  failures=1
else
  echo "PASS current-mattpocock-repository"
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
    "## Phase 6 — exact-candidate review",
    "git push -u origin",
    "gh pr view <literal-branch>",
    "record success <candidate-sha> --pr <literal-pr-number>",
    "## Phase 8 — merge and reconcile",
    "Confirm actual `MERGED` state",
]
positions = [s.index(value) for value in needles]
assert positions == sorted(positions), positions
PY

exit "$failures"
