#!/usr/bin/env bash
set -u

DIR="$(cd "$(dirname "$0")/../plugins/codex-tuner/scripts/execute-task" && pwd)"
P="$DIR/preflight.sh"
R="$DIR/runctl.sh"
RUNS_REL=".agent-state/codex-tuner/execute-task-runs"
fails=0

TEST_TOOLS="$(mktemp -d)" || exit 1
TEST_TOOLS="$(CDPATH='' cd -- "$TEST_TOOLS" && pwd -P)" || exit 1
REVIEWER_ROOT="$TEST_TOOLS/codex-cc-triage"
MARKER_FILE="$TEST_TOOLS/authoritative-marker"
THREAD_FILE="$TEST_TOOLS/authoritative-thread"
mkdir -p "$REVIEWER_ROOT/skills/claude-review" "$REVIEWER_ROOT/scripts"
printf '%s\n' '--required CODEX_CC_REQUIRED_REVIEW APPROVE' > "$REVIEWER_ROOT/skills/claude-review/SKILL.md"
cat > "$REVIEWER_ROOT/scripts/review-state.sh" <<'REVIEW_STATE_STUB'
#!/usr/bin/env bash
# Emits CODEX_CC_REQUIRED_REVIEW APPROVE only from this authoritative state stub.
[ -z "${CODEX_CC_TRIAGE_STATE_DIR:-}" ] || exit 9
[ -z "${CODEX_CC_TRIAGE_PYTHON_BIN:-}" ] || exit 9
[ "$1" = check ] && [ "$2" = "$(cat "$CODEX_TEST_THREAD_FILE")" ] && cat "$CODEX_TEST_MARKER_FILE"
REVIEW_STATE_STUB
chmod +x "$REVIEWER_ROOT/scripts/review-state.sh"
cat > "$TEST_TOOLS/codex" <<'CODEX_STUB'
#!/usr/bin/env bash
[ "$1:$2:$3" = "plugin:list:--json" ] || exit 1
jq -n --arg root "$CODEX_TEST_REVIEWER_ROOT" '{installed:[{
  pluginId:"codex-cc-triage@codex-cc-triage", installed:true, enabled:true,
  source:{source:"local",path:$root}
}]}'
CODEX_STUB
chmod +x "$TEST_TOOLS/codex"
export CODEX_TEST_REVIEWER_ROOT="$REVIEWER_ROOT" CODEX_TEST_MARKER_FILE="$MARKER_FILE"
export CODEX_TEST_THREAD_FILE="$THREAD_FILE"
PATH="$TEST_TOOLS:$PATH"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s%s\n' "$1" "${2:+ ($2)}"; fails=1; }
runctl() { EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$R" "$@"; }
evidence() {
  text="$1"; shift
  printf '%s\n' "$text" | runctl "$@"
}

make_repo() {
  REPO="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q -b main && git config user.email test@example.com \
      && git config user.name test && mkdir -p docs && printf 'base\n' > file.txt \
      && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
      && git commit -qm init && git switch -qc task
  ) || exit 1
  EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" run-1 main --expected-branch task >/dev/null \
    || exit 1
  runctl init run-1 --mode auto --spec docs/spec.md >/dev/null || exit 1
}

complete_readiness() {
  evidence "DoR commands and prerequisites verified" gate run-1 record dor pass >/dev/null \
    && runctl phase run-1 complete readiness >/dev/null \
    && runctl phase run-1 enter planning >/dev/null
}

create_plan() {
  evidence "Implement the scoped behavior and regression test" \
    task run-1 add implement-feature implementation >/dev/null \
    && evidence "Run targeted, full, static, and runtime verification" \
      task run-1 add verify-tests testing >/dev/null \
    && evidence "Prove every acceptance criterion" \
      task run-1 add verify-acceptance acceptance >/dev/null \
    && evidence "Stage and commit the tested candidate" \
      task run-1 add finalize-candidate candidate >/dev/null \
    && evidence "Complete every exact-candidate review" \
      task run-1 add review-candidate review >/dev/null \
    && evidence "Publish, verify CI and DoD, then reconcile" \
      task run-1 add deliver-candidate delivery >/dev/null \
    && evidence "update_plan published every lifecycle item with one in progress" \
      gate run-1 record planning pass >/dev/null \
    && runctl phase run-1 complete planning >/dev/null \
    && runctl phase run-1 enter implementation >/dev/null
}

complete_implementation() {
  runctl task run-1 start implement-feature >/dev/null \
    && evidence "Implementation and scoped test completed" \
      task run-1 complete implement-feature >/dev/null \
    && runctl phase run-1 complete implementation >/dev/null \
    && runctl phase run-1 enter testing >/dev/null
}

complete_testing_to_candidate() {
  runctl task run-1 start verify-tests >/dev/null \
    && evidence "targeted/full test commands passed" \
      task run-1 complete verify-tests >/dev/null \
    && evidence "targeted/full test commands passed" gate run-1 record testing pass >/dev/null \
    && runctl phase run-1 complete testing >/dev/null \
    && runctl phase run-1 enter acceptance >/dev/null \
    && runctl task run-1 start verify-acceptance >/dev/null \
    && evidence "machine acceptance passed" \
      task run-1 complete verify-acceptance >/dev/null \
    && evidence "machine acceptance passed" gate run-1 record acceptance pass >/dev/null \
    && runctl phase run-1 complete acceptance >/dev/null \
    && runctl phase run-1 enter candidate >/dev/null
}

record_candidate_and_enter_review() {
  SHA="$(git -C "$REPO" rev-parse HEAD)"
  runctl candidate run-1 record "$SHA" >/dev/null \
    && runctl task run-1 start finalize-candidate >/dev/null \
    && evidence "tested clean candidate recorded at $SHA" \
      task run-1 complete finalize-candidate >/dev/null \
    && runctl phase run-1 complete candidate >/dev/null \
    && runctl phase run-1 enter review >/dev/null
}

approve_all() {
  SHA="$(git -C "$REPO" rev-parse HEAD)"
  for reviewer in owner-review mattpocock; do
    evidence "$reviewer approved exact candidate" \
      review run-1 record "$reviewer" APPROVE "$SHA" >/dev/null || return 1
  done
  claude_stub_agrees
  evidence "$(claude_approval_marker)" \
    review run-1 record claude APPROVE "$SHA" >/dev/null \
    && runctl task run-1 start review-candidate >/dev/null \
    && evidence "all required reviews approved $SHA" \
      task run-1 complete review-candidate >/dev/null
}

claude_approval_marker() {
  state="$REPO/$RUNS_REL/run-1.state.json"
  sha="$(git -C "$REPO" rev-parse HEAD)"
  tree="$(jq -r '.candidate.tree_sha' "$state")"
  base="$(jq -r '.base_sha' "$state")"
  spec="$(jq -r '.spec' "$state")"
  thread="$(runctl reviewer-thread run-1)"
  printf 'CODEX_CC_REQUIRED_REVIEW APPROVE thread=%s head=%s tree=%s fingerprint=%064d base_sha=%s spec_path=%s\n' \
    "$thread" "$sha" "$tree" 1 "$base" "$spec"
}

claude_stub_agrees() {
  runctl reviewer-thread run-1 > "$THREAD_FILE"
  claude_approval_marker > "$MARKER_FILE"
}

prepare_candidate() {
  complete_readiness && create_plan || return 1
  runctl task run-1 start implement-feature >/dev/null || return 1
  printf 'implementation\n' >> "$REPO/file.txt"
  (cd "$REPO" && git add file.txt && git commit -qm implementation) || return 1
  evidence "Implementation and scoped test completed" \
    task run-1 complete implement-feature >/dev/null || return 1
  runctl phase run-1 complete implementation >/dev/null \
    && runctl phase run-1 enter testing >/dev/null || return 1
  complete_testing_to_candidate && record_candidate_and_enter_review
}

# State is adjacent to the journal, validates ownership, and init is idempotent.
make_repo
STATE="$REPO/$RUNS_REL/run-1.state.json"
if [ -f "$STATE" ] \
  && jq -e '.schema_version == 1 and .phase == {name:"readiness",status:"in_progress"} and
    .required_reviewers == ["owner-review","mattpocock","claude"]' "$STATE" >/dev/null \
  && runctl init run-1 --mode auto --spec docs/spec.md >/dev/null; then
  pass "state-init-idempotent"
else
  fail "state-init-idempotent"
fi
runctl init run-1 --mode auto --spec ./docs/spec.md >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r '.spec' "$STATE")" = "docs/spec.md" ]; then
  pass "spec-path-is-canonicalized"
else
  fail "spec-path-is-canonicalized" "rc=$rc spec=$(jq -r '.spec' "$STATE")"
fi
runctl init run-1 --mode auto >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "run-requires-a-committed-spec" \
  || fail "run-requires-a-committed-spec" "rc=$rc"
runctl init run-1 --mode auto --mode interactive --spec docs/spec.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "duplicate-init-mode-is-rejected" \
  || fail "duplicate-init-mode-is-rejected" "rc=$rc"
runctl init run-1 --mode auto --spec docs/spec.md --spec docs/spec.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "duplicate-init-spec-is-rejected" \
  || fail "duplicate-init-spec-is-rejected" "rc=$rc"
jq '.spec = null' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
runctl init run-1 --mode auto --spec docs/spec.md >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r '.spec' "$STATE")" = docs/spec.md ]; then
  pass "early-null-spec-state-is-migrated"
else
  fail "early-null-spec-state-is-migrated" "rc=$rc"
fi

SCHEMA="$DIR/../../schemas/run-state.schema.json"
STATE_KEYS="$(jq -c 'keys | sort' "$STATE")"
SCHEMA_KEYS="$(jq -c '.required | sort' "$SCHEMA")"
STATE_CI_KEYS="$(jq -c '.ci | keys | sort' "$STATE")"
SCHEMA_CI_KEYS="$(jq -c '.properties.ci.required | sort' "$SCHEMA")"
if [ "$STATE_KEYS" = "$SCHEMA_KEYS" ] && [ "$STATE_CI_KEYS" = "$SCHEMA_CI_KEYS" ] \
    && jq -e '
      .properties.required_reviewers.const == ["owner-review","mattpocock","claude"] and
      (.properties.run_id."$ref" | endswith("/runId")) and
      (."$defs".runId.pattern | contains("{0,79}")) and
      (."$defs".task.properties.phase.enum | length) == 6 and
      (.properties.candidate.oneOf | length) == 2 and
      (.properties.ci.oneOf | length) == 3 and
      (.allOf | length) == 2
    ' "$SCHEMA" >/dev/null; then
  pass "runtime-state-keys-match-published-schema"
else
  fail "runtime-state-keys-match-published-schema" \
    "state=$STATE_KEYS schema=$SCHEMA_KEYS ci=$STATE_CI_KEYS ci_schema=$SCHEMA_CI_KEYS"
fi

# Phase order is executable, not prose.
runctl phase run-1 enter implementation >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "illegal-transition-rejected" \
  || fail "illegal-transition-rejected" "rc=$rc"

# Active resume is the idempotent phase-entry read used at every /run boundary.
OUT="$(runctl resume run-1 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$OUT" | jq -e '.status == "active" and .phase.name == "readiness"' >/dev/null 2>&1; } \
  && pass "active-resume-is-idempotent" \
  || fail "active-resume-is-idempotent" "rc=$rc out=$OUT"

# One branch cannot have two authoritative active runs.
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" run-2 main --expected-branch task >/dev/null || exit 1
runctl init run-2 --mode auto --spec docs/spec.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "second-active-run-on-branch-rejected" \
  || fail "second-active-run-on-branch-rejected" "rc=$rc"

# Read/status operations re-check branch ownership.
(cd "$REPO" && git switch -qc other) >/dev/null 2>&1
runctl status run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "cross-branch-state-rejected" \
  || fail "cross-branch-state-rejected" "rc=$rc"
(cd "$REPO" && git switch -q task) >/dev/null 2>&1

# Explicit block/unblock is the only non-terminal hard-stop escape for an auto run.
evidence "waiting for a user-owned migration" block run-1 >/dev/null
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" run-2 main --expected-branch task >/dev/null || exit 1
runctl init run-2 --mode auto --spec docs/spec.md >/dev/null || exit 1
runctl resume run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "resume-cannot-duplicate-active-owner" \
  || fail "resume-cannot-duplicate-active-owner" "rc=$rc"
evidence "release branch ownership" block run-2 >/dev/null
[ "$(jq -r '.status' "$STATE")" = "blocked" ]
OUT="$(runctl resume run-1 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$OUT" | grep -q "runctl.sh unblock" \
    && [ "$(jq -r '.status' "$STATE")" = "blocked" ]; } \
  && pass "resume-does-not-clear-a-block" || fail "resume-does-not-clear-a-block" "rc=$rc out=$OUT"
runctl unblock run-1 < /dev/null >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "unblock-requires-a-recorded-decision" \
  || fail "unblock-requires-a-recorded-decision" "rc=$rc"
evidence "user resolved the migration" unblock run-1 >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(jq -r '.status' "$STATE")" = "active" ] \
    && grep -q 'decision: user resolved the migration' "$REPO/$RUNS_REL/run-1.md"; then
  pass "block-unblock-owned-state"
else
  fail "block-unblock-owned-state" "rc=$rc"
fi

complete_readiness && create_plan || exit 1
FIFO="$REPO/blocking-stdin"
mkfifo "$FIFO" || exit 1
( exec 9>"$FIFO"; sleep 30 ) & fifo_holder=$!
( runctl task run-1 complete implement-feature < "$FIFO" >/dev/null 2>&1 ) & blocked_writer=$!
sleep 1
( runctl task run-1 start implement-feature >"$REPO/probe.out" 2>&1; printf '%s\n' "$?" > "$REPO/probe.rc" ) &
probe=$!
waited=0
while [ ! -f "$REPO/probe.rc" ] && [ "$waited" -lt 20 ]; do sleep 0.5; waited=$((waited + 1)); done
kill "$probe" "$fifo_holder" "$blocked_writer" 2>/dev/null
wait "$probe" "$fifo_holder" "$blocked_writer" 2>/dev/null
rc="$(cat "$REPO/probe.rc" 2>/dev/null || printf 'still-blocked')"
[ "$rc" = "0" ] && pass "blocked-stdin-does-not-hold-the-state-lock" \
  || fail "blocked-stdin-does-not-hold-the-state-lock" "rc=$rc"
rm -rf "$REPO"

# Concurrent initialization is serialized across run IDs, so exactly one state can become active.
REPO="$(mktemp -d)" || exit 1
(
  cd "$REPO" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p docs && printf 'base\n' > file.txt \
    && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
    && git commit -qm init && git switch -qc task
) || exit 1
for run_id in parallel-a parallel-b; do
  EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" "$run_id" main --expected-branch task >/dev/null \
    || exit 1
done
(runctl init parallel-a --mode auto --spec docs/spec.md >/dev/null 2>&1) & pid_a=$!
(runctl init parallel-b --mode auto --spec docs/spec.md >/dev/null 2>&1) & pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
if { [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 1 ]; } \
    || { [ "$rc_a" -eq 1 ] && [ "$rc_b" -eq 0 ]; }; then
  pass "concurrent-init-allows-one-active-run"
else
  fail "concurrent-init-allows-one-active-run" "rc_a=$rc_a rc_b=$rc_b"
fi
rm -rf "$REPO"

# Stale-lock replacement is generation-safe under contention.
lock_race_ok=1
lock_race_trial=1
while [ "$lock_race_trial" -le 5 ]; do
  REPO="$(mktemp -d)" || exit 1
  RESULTS="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q -b main && git config user.email test@example.com \
      && git config user.name test && mkdir -p docs && printf 'base\n' > file.txt \
      && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
      && git commit -qm init && git switch -qc task
  ) || exit 1
  for n in 1 2 3 4 5 6 7 8; do
    EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" "race-$n" main --expected-branch task >/dev/null || exit 1
  done
  mkdir "$REPO/$RUNS_REL/.init.lock"
  printf '999999999999\n' > "$REPO/$RUNS_REL/.init.lock/pid"
  for n in 1 2 3 4 5 6 7 8; do
    (runctl init "race-$n" --mode auto --spec docs/spec.md >/dev/null 2>&1; printf '%s\n' "$?" > "$RESULTS/$n") &
  done
  wait
  successes="$(awk '$1 == 0 { total++ } END { print total + 0 }' "$RESULTS"/*)"
  active="$(find "$REPO/$RUNS_REL" -type f -name '*.state.json' | wc -l | tr -d ' ')"
  if [ "$successes" -ne 1 ] || [ "$active" -ne 1 ]; then lock_race_ok=0; break; fi
  rm -rf "$REPO" "$RESULTS"
  lock_race_trial=$((lock_race_trial + 1))
done
[ "$lock_race_ok" -eq 1 ] && pass "stale-init-lock-contention-is-serialized" \
  || fail "stale-init-lock-contention-is-serialized" "trial=$lock_race_trial successes=$successes active=$active"
[ "$lock_race_ok" -eq 1 ] || rm -rf "$REPO" "$RESULTS"

# A killed recovery owner cannot permanently brick or de-serialize initialization.
reclaim_race_ok=1
reclaim_trial=1
while [ "$reclaim_trial" -le 10 ]; do
  REPO="$(mktemp -d)" || exit 1
  RESULTS="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q -b main && git config user.email test@example.com \
      && git config user.name test && mkdir -p docs && printf 'base\n' > file.txt \
      && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
      && git commit -qm init && git switch -qc task
  ) || exit 1
  for n in 1 2 3 4 5 6 7 8; do
    EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" "orphan-$n" main --expected-branch task >/dev/null || exit 1
  done
  mkdir "$REPO/$RUNS_REL/.init.lock.reclaim"
  printf '999999999999\n' > "$REPO/$RUNS_REL/.init.lock.reclaim/pid"
  for n in 1 2 3 4 5 6 7 8; do
    (runctl init "orphan-$n" --mode auto --spec docs/spec.md >/dev/null 2>&1; printf '%s\n' "$?" > "$RESULTS/$n") &
  done
  wait
  successes="$(awk '$1 == 0 { total++ } END { print total + 0 }' "$RESULTS"/*)"
  active="$(find "$REPO/$RUNS_REL" -type f -name '*.state.json' | wc -l | tr -d ' ')"
  if [ "$successes" -ne 1 ] || [ "$active" -ne 1 ]; then reclaim_race_ok=0; break; fi
  rm -rf "$REPO" "$RESULTS"
  reclaim_trial=$((reclaim_trial + 1))
done
[ "$reclaim_race_ok" -eq 1 ] && pass "orphaned-init-reclaimer-is-recovered" \
  || fail "orphaned-init-reclaimer-is-recovered" \
    "trial=$reclaim_trial successes=$successes active=$active"
[ "$reclaim_race_ok" -eq 1 ] || rm -rf "$REPO" "$RESULTS"

# Reviewer threads stay within the peer contract and do not collide across linked worktrees.
REPO="$(mktemp -d)" || exit 1
WORKTREE="$(mktemp -d)" || exit 1
rmdir "$WORKTREE" || exit 1
(
  cd "$REPO" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p docs && printf 'base\n' > file.txt \
    && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
    && git commit -qm init && git switch -qc task-a \
    && git worktree add -qb task-b "$WORKTREE" main
) >/dev/null 2>&1 || exit 1
LONG_RUN_ID="$(printf 'a%.0s' $(seq 1 80))"
for checkout in "$REPO" "$WORKTREE"; do
  branch="$(git -C "$checkout" branch --show-current)"
  EXECUTE_TASK_PROJECT_DIR="$checkout" bash "$P" "$LONG_RUN_ID" main --expected-branch "$branch" >/dev/null || exit 1
  EXECUTE_TASK_PROJECT_DIR="$checkout" bash "$R" init "$LONG_RUN_ID" --mode auto --spec docs/spec.md >/dev/null || exit 1
done
THREAD_A="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$R" reviewer-thread "$LONG_RUN_ID")"
THREAD_B="$(EXECUTE_TASK_PROJECT_DIR="$WORKTREE" bash "$R" reviewer-thread "$LONG_RUN_ID")"
printf 'complete the first branch run later\n' \
  | EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$R" block "$LONG_RUN_ID" >/dev/null || exit 1
LONG_RUN_ID_TWO="$(printf 'a%.0s' $(seq 1 79))b"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$P" "$LONG_RUN_ID_TWO" main --expected-branch task-a >/dev/null || exit 1
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$R" init "$LONG_RUN_ID_TWO" --mode auto --spec docs/spec.md >/dev/null || exit 1
THREAD_C="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$R" reviewer-thread "$LONG_RUN_ID_TWO")"
THREAD_FORMAT_COUNT="$(printf '%s\n%s\n%s\n' "$THREAD_A" "$THREAD_B" "$THREAD_C" \
  | grep -Ec '^review-[a-z0-9._-]+-[0-9a-f]{12}$')"
if [ "${#THREAD_A}" -le 80 ] && [ "${#THREAD_B}" -le 80 ] \
    && [ "${#THREAD_C}" -le 80 ] \
    && [ "$THREAD_A" != "$THREAD_B" ] && [ "$THREAD_A" != "$THREAD_C" ] \
    && [ "$THREAD_FORMAT_COUNT" -eq 3 ]; then
  pass "reviewer-thread-is-bounded-and-run-unique"
else
  fail "reviewer-thread-is-bounded-and-run-unique" "a=$THREAD_A b=$THREAD_B c=$THREAD_C"
fi
git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
rm -rf "$REPO"

# Specs move from the planning area to the archive while implementation owns mutations. State
# follows only a staged/committed relocation; a copy that leaves the old tracked path cannot pass.
make_repo
complete_readiness || exit 1
evidence "Impossible late readiness task" task run-1 add late-readiness readiness >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "past-phase-task-is-rejected" \
  || fail "past-phase-task-is-rejected" "rc=$rc"
evidence "Reserved fix task" task run-1 add review-fix-1 implementation >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "fix-task-namespace-is-reserved" \
  || fail "fix-task-namespace-is-reserved" "rc=$rc"
evidence "Implementation only" task run-1 add implement-only implementation >/dev/null
runctl phase run-1 complete planning >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "planning-requires-full-lifecycle" \
  || fail "planning-requires-full-lifecycle" "rc=$rc"
rm -rf "$REPO"

make_repo
complete_readiness && create_plan || exit 1
mkdir -p "$REPO/docs/archive"
cp "$REPO/docs/spec.md" "$REPO/docs/archive/spec-copy.md"
(cd "$REPO" && git add docs/archive/spec-copy.md) >/dev/null 2>&1
runctl spec run-1 relocate docs/archive/spec-copy.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "spec-copy-is-not-relocation" \
  || fail "spec-copy-is-not-relocation" "rc=$rc"
(cd "$REPO" && git reset -q docs/archive/spec-copy.md && rm -f docs/archive/spec-copy.md \
  && git mv docs/spec.md docs/archive/spec.md) >/dev/null 2>&1
runctl spec run-1 relocate docs/archive/spec.md >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$(jq -r '.spec' "$REPO/$RUNS_REL/run-1.state.json")" = "docs/archive/spec.md" ]; then
  pass "tracked-spec-relocation-updates-state"
else
  fail "tracked-spec-relocation-updates-state" "rc=$rc"
fi
rm -rf "$REPO"

# Prepared commit/PR text is repository-bound, outside the candidate, and link-safe.
make_repo
PREPARED="$(runctl prepare run-1 commit-message)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -f "$PREPARED" ]; } && pass "prepare-returns-a-usable-path" \
  || fail "prepare-returns-a-usable-path" "rc=$rc path=$PREPARED"
REPO_REAL_PREP="$(cd "$REPO" && pwd -P)"
case "$PREPARED" in
  "$REPO_REAL_PREP"/*) fail "prepared-file-is-outside-the-repository" "$PREPARED" ;;
  /*) pass "prepared-file-is-outside-the-repository" ;;
  *) fail "prepared-file-is-outside-the-repository" "not absolute: $PREPARED" ;;
esac
printf 'subject\n' > "$PREPARED"
[ "$(runctl prepare run-1 commit-message)" = "$PREPARED" ] \
  && [ "$(cat "$PREPARED")" = subject ] \
  && pass "prepare-is-stable-without-truncation" || fail "prepare-is-stable-without-truncation"
ALTERNATE_TMP="$TEST_TOOLS/alternate-tmp"
mkdir -p "$ALTERNATE_TMP"
if [ "$(TMPDIR="$ALTERNATE_TMP" runctl prepare run-1 commit-message)" = "$PREPARED" ] \
    && [ "$(cat "$PREPARED")" = subject ]; then
  pass "prepared-path-survives-a-changed-tmpdir"
else
  fail "prepared-path-survives-a-changed-tmpdir"
fi
runctl prepare run-1 arbitrary-note >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "prepare-allows-only-owned-workflow-files" \
  || fail "prepare-allows-only-owned-workflow-files" "rc=$rc"
PREPARED_DIR="$(dirname "$PREPARED")"
PREPARED_VICTIM="$PREPARED_DIR/hardlink-victim"
printf 'unchanged\n' > "$PREPARED_VICTIM"
FILE_BEFORE="$(cat "$PREPARED_VICTIM")"
ln "$PREPARED_VICTIM" "$PREPARED_DIR/pr-body" 2>/dev/null
runctl prepare run-1 pr-body >/dev/null 2>&1; rc=$?
if [ -e "$PREPARED_DIR/pr-body" ]; then
  { [ "$rc" -eq 1 ] && [ "$(cat "$PREPARED_VICTIM")" = "$FILE_BEFORE" ]; } \
    && pass "prepare-refuses-a-hard-linked-destination" \
    || fail "prepare-refuses-a-hard-linked-destination" "rc=$rc"
  rm -f "$PREPARED_DIR/pr-body" "$PREPARED_VICTIM"
else
  fail "prepare-refuses-a-hard-linked-destination" "fixture missing"
  rm -f "$PREPARED_VICTIM"
fi
IN_REPO_TMP="$REPO/in-repo-tmp"
mkdir -p "$IN_REPO_TMP"
IN_REPO_PREPARED="$(TMPDIR="$IN_REPO_TMP" runctl prepare run-1 pr-body 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$IN_REPO_PREPARED" = "$PREPARED_DIR/pr-body" ] \
    && [ -z "$(find "$IN_REPO_TMP" -mindepth 1 -print -quit)" ]; then
  pass "stored-prepared-path-ignores-a-later-in-repo-tmpdir"
else
  fail "stored-prepared-path-ignores-a-later-in-repo-tmpdir" "rc=$rc path=$IN_REPO_PREPARED"
fi

FIRST_REPO="$REPO"
SECOND_REPO="$(mktemp -d)" || exit 1
(
  cd "$SECOND_REPO" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p docs && printf 'other\n' > file.txt \
    && printf '# Spec\n' > docs/spec.md && git add file.txt docs/spec.md \
    && git commit -qm init && git switch -qc task
) || exit 1
EXECUTE_TASK_PROJECT_DIR="$SECOND_REPO" bash "$P" run-1 main --expected-branch task >/dev/null || exit 1
EXECUTE_TASK_PROJECT_DIR="$SECOND_REPO" bash "$R" init run-1 --mode auto --spec docs/spec.md >/dev/null || exit 1
SECOND_PREPARED="$(EXECUTE_TASK_PROJECT_DIR="$SECOND_REPO" bash "$R" prepare run-1 commit-message)"
[ "$SECOND_PREPARED" != "$PREPARED" ] && pass "prepared-path-is-repository-bound" \
  || fail "prepared-path-is-repository-bound" "$SECOND_PREPARED"
rm -f "$SECOND_PREPARED"
rmdir "$(dirname "$SECOND_PREPARED")" 2>/dev/null || true
rm -rf "$SECOND_REPO"
REPO="$FIRST_REPO"
evidence "stop here" block run-1 >/dev/null
runctl prepare run-1 commit-message >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "prepare-refuses-a-blocked-run" \
  || fail "prepare-refuses-a-blocked-run" "rc=$rc"
rm -f "$PREPARED" "$PREPARED_DIR/pr-body"
rmdir "$PREPARED_DIR" 2>/dev/null || true
rm -rf "$REPO"

# A candidate cannot pass review without every required exact-SHA verdict.
make_repo
prepare_candidate || { fail "candidate-fixture"; rm -rf "$REPO"; exit "$fails"; }
SHA="$(git -C "$REPO" rev-parse HEAD)"
evidence "owner review approved" review run-1 record owner-review APPROVE "$SHA" >/dev/null
evidence "mattpocock approved" review run-1 record mattpocock APPROVE "$SHA" >/dev/null
runctl task run-1 start review-candidate >/dev/null
evidence "review task completed for gate validation" \
  task run-1 complete review-candidate >/dev/null
runctl phase run-1 complete review >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "missing-claude-review-blocks" \
  || fail "missing-claude-review-blocks" "rc=$rc"

# Approval is invalid as soon as either HEAD or the worktree differs from the candidate.
evidence "claude approved" review run-1 record claude APPROVE "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "claude-approval-requires-self-verified-marker" \
  || fail "claude-approval-requires-self-verified-marker" "rc=$rc"
bad_marker="$(claude_approval_marker | sed 's/fingerprint=/digest=/')"
evidence "$bad_marker" review run-1 record claude APPROVE "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "claude-approval-requires-fingerprint-label" \
  || fail "claude-approval-requires-fingerprint-label" "rc=$rc"
zero_marker="$(claude_approval_marker | sed 's/fingerprint=[0-9a-f]*/fingerprint=0000000000000000000000000000000000000000000000000000000000000000/')"
printf '%s\n' "$(claude_approval_marker)" > "$MARKER_FILE"
evidence "$zero_marker" review run-1 record claude APPROVE "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "hand-written-zero-fingerprint-is-not-authority" \
  || fail "hand-written-zero-fingerprint-is-not-authority" "rc=$rc"
claude_stub_agrees
export CODEX_CC_TRIAGE_STATE_DIR="$TEST_TOOLS/forged-state"
export CODEX_CC_TRIAGE_PYTHON_BIN="$TEST_TOOLS/forged-python"
evidence "$(claude_approval_marker)" review run-1 record claude APPROVE "$SHA" >/dev/null 2>&1; rc=$?
unset CODEX_CC_TRIAGE_STATE_DIR CODEX_CC_TRIAGE_PYTHON_BIN
[ "$rc" -eq 0 ] && pass "ambient-reviewer-overrides-are-stripped" \
  || fail "ambient-reviewer-overrides-are-stripped" "rc=$rc"
printf 'post-review mutation\n' >> "$REPO/file.txt"
runctl can-advance run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "dirty-tree-invalidates-review" \
  || fail "dirty-tree-invalidates-review" "rc=$rc"
(cd "$REPO" && git add file.txt && git commit -qm post-review-mutation) >/dev/null 2>&1
runctl can-advance run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "new-head-invalidates-review" \
  || fail "new-head-invalidates-review" "rc=$rc"
rm -rf "$REPO"

# REQUEST_CHANGES is a blocking current verdict and leaves review only through the explicit fix loop.
make_repo
prepare_candidate || { fail "request-changes-fixture"; rm -rf "$REPO"; exit "$fails"; }
SHA="$(git -C "$REPO" rev-parse HEAD)"
evidence "owner review requested changes" review run-1 record owner-review REQUEST_CHANGES "$SHA" >/dev/null
evidence "matt approved" review run-1 record mattpocock APPROVE "$SHA" >/dev/null
claude_stub_agrees
evidence "$(claude_approval_marker)" review run-1 record claude APPROVE "$SHA" >/dev/null
runctl task run-1 start review-candidate >/dev/null
evidence "review attempt completed with blocking verdict" \
  task run-1 complete review-candidate >/dev/null
runctl phase run-1 complete review >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "request-changes-blocks-review" \
  || fail "request-changes-blocks-review" "rc=$rc"
evidence "fresh approval without a disposition" \
  review run-1 record owner-review APPROVE "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "same-candidate-approval-requires-a-disposition" \
  || fail "same-candidate-approval-requires-a-disposition" "rc=$rc"
evidence "finding: owner-review-1
disposition: refuted because the invariant already holds
source: file.txt:1" \
  review run-1 record owner-review APPROVE "$SHA" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && jq -e --arg sha "$SHA" '
    [.review_history[] | select(.reviewer == "owner-review" and .sha == $sha) | .verdict] ==
      ["REQUEST_CHANGES", "APPROVE"]
  ' "$REPO/$RUNS_REL/run-1.state.json" >/dev/null; then
  pass "same-candidate-disposition-allows-fresh-approval"
else
  fail "same-candidate-disposition-allows-fresh-approval" "rc=$rc"
fi
rm -rf "$REPO"

# An in-repository TMPDIR must not become part of the worktree fingerprint.
make_repo
complete_readiness && create_plan || exit 1
runctl task run-1 start implement-feature >/dev/null
evidence "Implementation completed before stable snapshot" \
  task run-1 complete implement-feature >/dev/null
mkdir "$REPO/ambient-tmp"
TMPDIR="$REPO/ambient-tmp" runctl phase run-1 complete implementation >/dev/null 2>&1; rc=$?
SNAPSHOT="$(jq -r '[.gates[] | select(.id == "implementation-tree")][-1].tree_sha // empty' \
  "$REPO/$RUNS_REL/run-1.state.json")"
HEAD_TREE="$(git -C "$REPO" rev-parse HEAD^{tree})"
if [ "$rc" -eq 0 ] && [ "$SNAPSHOT" = "$HEAD_TREE" ]; then
  pass "in-repo-tmpdir-does-not-pollute-snapshot"
else
  fail "in-repo-tmpdir-does-not-pollute-snapshot" "rc=$rc snapshot=$SNAPSHOT head=$HEAD_TREE"
fi
rm -rf "$REPO"

# An implementation snapshot failure must not advance the phase.
make_repo
complete_readiness && create_plan || exit 1
runctl task run-1 start implement-feature >/dev/null
evidence "Implementation completed before snapshot" \
  task run-1 complete implement-feature >/dev/null
MISSING_INDEX="$REPO/does-not-exist/index"
GIT_INDEX_FILE="$MISSING_INDEX" runctl phase run-1 complete implementation >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ] \
    && jq -e '.phase == {name:"implementation",status:"in_progress"} and
      all(.gates[]; .id != "implementation-tree")' \
      "$REPO/$RUNS_REL/run-1.state.json" >/dev/null; then
  pass "implementation-snapshot-failure-does-not-complete-phase"
else
  fail "implementation-snapshot-failure-does-not-complete-phase" "rc=$rc"
fi
rm -rf "$REPO"

# Testing cannot absorb a mutation made after implementation closed.
make_repo
complete_readiness && create_plan && complete_implementation || exit 1
printf 'mutation during testing\n' >> "$REPO/file.txt"
OUT="$(evidence "tests passed after an illicit edit" gate run-1 record testing pass 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && pass "testing-cannot-absorb-a-mutation" \
  || fail "testing-cannot-absorb-a-mutation" "rc=$rc out=$OUT"
rm -rf "$REPO"

# Candidate content must still be exactly the tested content.
make_repo
complete_readiness && create_plan || exit 1
runctl task run-1 start implement-feature >/dev/null
printf 'tested implementation\n' >> "$REPO/file.txt"
(cd "$REPO" && git add file.txt && git commit -qm tested-implementation) >/dev/null 2>&1
evidence "implementation completed" task run-1 complete implement-feature >/dev/null
runctl phase run-1 complete implementation >/dev/null
runctl phase run-1 enter testing >/dev/null
evidence "tests passed on this worktree" gate run-1 record testing pass >/dev/null
runctl task run-1 start verify-tests >/dev/null
evidence "testing task completed" task run-1 complete verify-tests >/dev/null
runctl phase run-1 complete testing >/dev/null
runctl phase run-1 enter acceptance >/dev/null
evidence "acceptance passed" gate run-1 record acceptance pass >/dev/null
runctl task run-1 start verify-acceptance >/dev/null
evidence "acceptance task completed" task run-1 complete verify-acceptance >/dev/null
runctl phase run-1 complete acceptance >/dev/null
runctl phase run-1 enter candidate >/dev/null
printf 'untested mutation\n' >> "$REPO/file.txt"
(cd "$REPO" && git add file.txt && git commit -qm untested-mutation) >/dev/null 2>&1
SHA="$(git -C "$REPO" rev-parse HEAD)"
runctl candidate run-1 record "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "candidate-must-match-tested-tree" \
  || fail "candidate-must-match-tested-tree" "rc=$rc"
rm -rf "$REPO"

# A testing/acceptance/candidate/review/delivery failure returns only through the explicit fix loop.
make_repo
complete_readiness && create_plan && complete_implementation || exit 1
evidence "targeted test failed" gate run-1 record testing fail >/dev/null
evidence "same state claimed green" gate run-1 record testing pass >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "failed-testing-gate-cannot-be-overwritten" \
  || fail "failed-testing-gate-cannot-be-overwritten" "rc=$rc"
evidence "test exposed another implementation defect" phase run-1 fix >/dev/null
if jq -e '.phase == {name:"implementation",status:"in_progress"} and .fix_round == 1 and
    any(.tasks[]; .id == "review-fix-1" and .status == "pending") and
    .candidate.sha == null and .ci.status == "pending"' \
    "$REPO/$RUNS_REL/run-1.state.json" >/dev/null; then
  pass "testing-fix-loop-creates-task-and-invalidates"
else
  fail "testing-fix-loop-creates-task-and-invalidates"
fi
rm -rf "$REPO"

# Runtime validation agrees with the published bounded/unique schema rules.
make_repo
complete_readiness && create_plan && complete_implementation || exit 1
STATE="$REPO/$RUNS_REL/run-1.state.json"
jq '.fix_round = 999999' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
evidence "one more fix" phase run-1 fix >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && [ "$(jq -r '.fix_round' "$STATE")" -eq 999999 ] \
  && pass "fix-loop-limit-rejected-before-arithmetic" \
  || fail "fix-loop-limit-rejected-before-arithmetic" "rc=$rc"
jq '.fix_round = 1000000' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
runctl status run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "out-of-range-fix-counter-invalidates-state" \
  || fail "out-of-range-fix-counter-invalidates-state" "rc=$rc"
jq '.fix_round = 0 | .completed_phases = ["readiness","planning","readiness"]' "$STATE" \
  > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
runctl status run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "duplicate-completed-phase-invalidates-state" \
  || fail "duplicate-completed-phase-invalidates-state" "rc=$rc"
cp "$STATE" "$STATE.invalid"
jq '.completed_phases = ["readiness","planning","implementation"] | .invalidations = [{}]' \
  "$STATE.invalid" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
runctl status run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "malformed-invalidation-invalidates-state" \
  || fail "malformed-invalidation-invalidates-state" "rc=$rc"
jq '.invalidations = [] | .created_at = "not-a-timestamp"' \
  "$STATE.invalid" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
runctl status run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "malformed-timestamp-invalidates-state" \
  || fail "malformed-timestamp-invalidates-state" "rc=$rc"
rm -rf "$REPO"

# Delivery accepts CI and DoD only for the immutable reviewed candidate.
make_repo
prepare_candidate && approve_all \
  && runctl phase run-1 complete review >/dev/null \
  && runctl phase run-1 enter delivery >/dev/null || exit 1
runctl task run-1 start deliver-candidate >/dev/null
evidence "delivery attempt completed for CI gate validation" \
  task run-1 complete deliver-candidate >/dev/null
SHA="$(git -C "$REPO" rev-parse HEAD)"
WRONG_SHA="$(git -C "$REPO" rev-parse main)"
evidence "stale CI run" ci run-1 record success "$WRONG_SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "wrong-ci-sha-rejected" \
  || fail "wrong-ci-sha-rejected" "rc=$rc"
evidence "required checks failed" ci run-1 record failure "$SHA" >/dev/null
runctl phase run-1 complete delivery >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "failed-ci-blocks-delivery" \
  || fail "failed-ci-blocks-delivery" "rc=$rc"
evidence "same candidate CI retried green" ci run-1 record success "$SHA" --pr 42 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "failed-ci-cannot-be-overwritten" \
  || fail "failed-ci-cannot-be-overwritten" "rc=$rc"
rm -rf "$REPO"

# A fresh candidate may record live hosted CI; the state remains bound to that PR until merge.
make_repo
prepare_candidate && approve_all \
  && runctl phase run-1 complete review >/dev/null \
  && runctl phase run-1 enter delivery >/dev/null || exit 1
FINAL_PREPARED="$(runctl prepare run-1 pr-body)" || exit 1
printf 'pull request body\n' > "$FINAL_PREPARED"
SHA="$(git -C "$REPO" rev-parse HEAD)"
WRONG_SHA="$(git -C "$REPO" rev-parse main)"

GH_STUB="$(mktemp -d)" || exit 1
cat > "$GH_STUB/gh" <<'GH_STUB_SCRIPT'
#!/usr/bin/env bash
case "$1:$2" in
  pr:view) printf '{"number":42,"state":"%s","headRefOid":"%s","headRefName":"%s","baseRefName":"%s","mergeCommit":{"oid":"merge-sha"}}\n' \
    "${GH_TEST_PR_STATE:-OPEN}" "$GH_TEST_SHA" "${GH_TEST_HEAD:-task}" "${GH_TEST_BASE:-main}" ;;
  pr:checks)
    if [ "$GH_TEST_CHECKS" = none ]; then
      echo "no checks reported on the 'task' branch" >&2
      exit 1
    fi
    printf '%s\n' "$GH_TEST_CHECKS"
    ;;
  *) exit 1 ;;
esac
GH_STUB_SCRIPT
chmod +x "$GH_STUB/gh"
export GH_TEST_SHA="$WRONG_SHA"
export GH_TEST_CHECKS='[{"bucket":"pass","name":"test","state":"SUCCESS"}]'
PATH="$GH_STUB:$PATH"
evidence "checks passed on stale PR head" ci run-1 record success "$SHA" --pr 42 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "stale-pr-head-not-green" \
  || fail "stale-pr-head-not-green" "rc=$rc"
export GH_TEST_SHA="$SHA"
export GH_TEST_HEAD="wrong-task"
export GH_TEST_BASE="main"
evidence "checks passed for the wrong PR head branch" ci run-1 record success "$SHA" --pr 42 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "wrong-pr-head-branch-not-green" \
  || fail "wrong-pr-head-branch-not-green" "rc=$rc"
export GH_TEST_HEAD="task"
export GH_TEST_BASE="wrong-base"
evidence "checks passed for the wrong PR target" ci run-1 record success "$SHA" --pr 42 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "wrong-pr-target-not-green" \
  || fail "wrong-pr-target-not-green" "rc=$rc"
export GH_TEST_BASE="main"
export GH_TEST_CHECKS='none'
OUT="$(evidence "no required checks" ci run-1 record success "$SHA" --pr 42 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$OUT" | grep -q 'no required checks configured on GitHub'; } \
  && pass "absent-required-checks-names-configuration-gap" \
  || fail "absent-required-checks-names-configuration-gap" "rc=$rc out=$OUT"
export GH_TEST_CHECKS='[{"bucket":"pass","name":"test","state":"SUCCESS"}]'
evidence "required checks passed" ci run-1 record success "$SHA" --pr 42 >/dev/null
[ "$(jq -r '.ci.pr_number' "$REPO/$RUNS_REL/run-1.state.json")" = "42" ] \
  && pass "successful-ci-is-bound-to-pr" || fail "successful-ci-is-bound-to-pr"
export GH_TEST_CHECKS='[{"bucket":"fail","name":"test","state":"FAILURE"}]'
runctl phase run-1 complete delivery >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "ci-regression-blocks-delivery-at-use-time" \
  || fail "ci-regression-blocks-delivery-at-use-time" "rc=$rc"
export GH_TEST_CHECKS='[{"bucket":"pass","name":"test","state":"SUCCESS"}]'
evidence "DoD verified on candidate" gate run-1 record dod pass --sha "$SHA" >/dev/null
runctl task run-1 start deliver-candidate >/dev/null
evidence "PR, current-SHA CI, and DoD verified" \
  task run-1 complete deliver-candidate >/dev/null
runctl phase run-1 complete delivery >/dev/null
evidence "late CI failure" ci run-1 record failure "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "completed-delivery-ci-is-immutable" \
  || fail "completed-delivery-ci-is-immutable" "rc=$rc"
evidence "late DoD failure" gate run-1 record dod fail --sha "$SHA" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "completed-delivery-dod-is-immutable" \
  || fail "completed-delivery-dod-is-immutable" "rc=$rc"
export GH_TEST_SHA="$WRONG_SHA"
runctl can-merge run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "pr-head-move-blocks-merge-time-check" \
  || fail "pr-head-move-blocks-merge-time-check" "rc=$rc"
export GH_TEST_SHA="$SHA"
OUT="$(runctl can-merge run-1 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$OUT" | grep -q "$SHA"; } \
  && pass "exact-sha-delivery-can-merge" \
  || fail "exact-sha-delivery-can-merge" "rc=$rc out=$OUT"
evidence "premature completion claim" finish run-1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && pass "finish-requires-merged-pr" \
  || fail "finish-requires-merged-pr" "rc=$rc"
export GH_TEST_PR_STATE="MERGED"
FINISH_TMP="$TEST_TOOLS/finish-tmp"
mkdir -p "$FINISH_TMP"
TMPDIR="$FINISH_TMP" evidence "PR merged; issue/spec/branch reconciled" finish run-1 >/dev/null
[ "$(jq -r '.status + ":" + .phase.name' "$REPO/$RUNS_REL/run-1.state.json")" = "completed:done" ] \
  && [ "$(jq -r '.completion_evidence' "$REPO/$RUNS_REL/run-1.state.json")" = "PR merged; issue/spec/branch reconciled" ] \
  && pass "finish-marks-terminal" || fail "finish-marks-terminal"
[ ! -e "$FINAL_PREPARED" ] && pass "finish-removes-prepared-files" \
  || fail "finish-removes-prepared-files" "$FINAL_PREPARED"
[ ! -e "$REPO/$RUNS_REL/run-1.prepared-dir" ] \
  && pass "finish-removes-prepared-path-state" \
  || fail "finish-removes-prepared-path-state"
rm -rf "$GH_STUB"
rm -rf "$REPO"
rm -rf "$TEST_TOOLS"

exit "$fails"
