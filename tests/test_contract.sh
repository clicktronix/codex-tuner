#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/codex-tuner/skills/spec/SKILL.md"
RUN="$ROOT/plugins/codex-tuner/skills/run/SKILL.md"
CONTRACT="$ROOT/workflow-contract.json"
failures=0

need() {
  name="$1"; pattern="$2"; file="$3"
  if grep -qF "$pattern" "$file"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    failures=1
  fi
}

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["version"] == "1.0.0" and len(d["invariants"]) == 14' "$CONTRACT" \
  && echo "PASS contract-manifest" || { echo "FAIL contract-manifest"; failures=1; }
need "spec-branch" "Create the task branch" "$SPEC"
need "spec-auto-ready" "auto_ready: yes|no" "$SPEC"
need "run-auto-ready-no" '`auto_ready: no` is authoritative' "$RUN"
need "run-resume" 'journal.sh" resume <literal-run-id>' "$RUN"
need "run-phase-boundary" "Apply the phase boundary" "$RUN"
need "run-explicit-stage" "git add -- <path-1> <path-2>" "$RUN"
need "run-guard-after-stage" "guard after staging" "$RUN"
need "run-current-sha-ci" "remote PR head equals the journaled SHA" "$RUN"
need "run-auto-post-merge-stop" "any outward action after merge" "$RUN"

exit "$failures"
