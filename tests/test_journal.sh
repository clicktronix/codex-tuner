#!/usr/bin/env bash
set -u

SCRIPTS="$(cd "$(dirname "$0")/../plugins/codex-tuner/scripts/execute-task" && pwd)"
STATE_REL=".agent-state/codex-tuner"
failures=0

PATH_REPO="$(mktemp -d)" || exit 1
(
  cd "$PATH_REPO" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && printf 'base\n' > file.txt && git add file.txt \
    && git commit -qm init
) || exit 1
OUT="$(EXECUTE_TASK_PROJECT_DIR="$PATH_REPO" bash "$SCRIPTS/journal.sh" path pure-path 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
  && [ "$OUT" = ".agent-state/codex-tuner/execute-task-runs/pure-path.md" ] \
  && [ ! -e "$PATH_REPO/.agent-state" ]; then
  echo "PASS path-has-no-state-side-effect"
else
  echo "FAIL path-has-no-state-side-effect (rc=$rc out=$OUT)"
  failures=1
fi
rm -rf "$PATH_REPO"

REPO="$(mktemp -d)" || exit 1
(
  cd "$REPO" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && printf 'base\n' > file.txt && git add file.txt \
    && git commit -qm init && git switch -qc task
) || exit 1

EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/preflight.sh" run-1 main --expected-branch task >/dev/null
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" append run-1 "focused tests passed"
if grep -q "focused tests passed" "$REPO/$STATE_REL/execute-task-runs/run-1.md"; then
  echo "PASS append"
else
  echo "FAIL append"
  failures=1
fi

before="$(wc -l < "$REPO/$STATE_REL/execute-task-runs/run-1.md")"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" append run-1 >/dev/null 2>&1
rc=$?
after="$(wc -l < "$REPO/$STATE_REL/execute-task-runs/run-1.md")"
if [ "$rc" -eq 1 ] && [ "$before" = "$after" ]; then
  echo "PASS empty-append-rejected"
else
  echo "FAIL empty-append-rejected"
  failures=1
fi

OUT="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" read run-1 2>&1)"
if printf '%s' "$OUT" | grep -q 'base SHA' && printf '%s' "$OUT" | grep -q 'focused tests passed'; then
  echo "PASS read"
else
  echo "FAIL read"
  failures=1
fi

for i in 1 2 3 4 5 6 7 8; do
  EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" append run-1 "entry $i" >/dev/null
done
OUT="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" resume run-1 3 2>&1)"
if printf '%s' "$OUT" | grep -q 'base SHA' \
  && printf '%s' "$OUT" | grep -q 'entry 8' \
  && printf '%s' "$OUT" | grep -q 'entry 6' \
  && ! printf '%s' "$OUT" | grep -q 'entry 5' \
  && printf '%s' "$OUT" | grep -q 'lines omitted'; then
  echo "PASS resume-bounded"
else
  echo "FAIL resume-bounded"
  failures=1
fi

EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" resume run-1 0 >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && echo "PASS resume-zero" || { echo "FAIL resume-zero"; failures=1; }

EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" resume run-1 banana >/dev/null 2>&1
rc=$?
[ "$rc" -eq 1 ] && echo "PASS resume-bad-count" || { echo "FAIL resume-bad-count"; failures=1; }

OUT="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" resume run-1 999999999999999999999 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT" | grep -q 'at most 7 digits'; then
  echo "PASS resume-huge-count-rejected"
else
  echo "FAIL resume-huge-count-rejected (rc=$rc out=$OUT)"
  failures=1
fi

(
  cd "$REPO" && printf 'second\n' > second.txt && git add second.txt && git commit -qm second
)
NEW_SHA="$(cd "$REPO" && git rev-parse HEAD)"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/preflight.sh" run-1 main --expected-branch task >/dev/null
OUT="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" resume run-1 1 2>&1)"
if printf '%s' "$OUT" | grep -q "$NEW_SHA" && printf '%s' "$OUT" | grep -q 'supersedes'; then
  echo "PASS resume-restart-base"
else
  echo "FAIL resume-restart-base"
  failures=1
fi

(cd "$REPO" && git switch -qc other)
cross_branch_ok=1
for operation in "append run-1 cross-branch" "read run-1" "resume run-1"; do
  # shellcheck disable=SC2086
  EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" $operation >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || cross_branch_ok=0
done
if [ "$cross_branch_ok" -eq 1 ]; then
  echo "PASS cross-branch-journal-operations-rejected"
else
  echo "FAIL cross-branch-journal-operations-rejected"
  failures=1
fi

rm -rf "$REPO"
exit "$failures"
