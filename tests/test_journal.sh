#!/usr/bin/env bash
set -u

SCRIPTS="$(cd "$(dirname "$0")/../plugins/codex-tuner/skills/execute-task/scripts" && pwd)"
failures=0
REPO="$(mktemp -d)" || exit 1
(
  cd "$REPO" && git init -q && git config user.email test@example.com \
    && git config user.name test && echo base > file.txt && git add file.txt \
    && git commit -qm init
) || exit 1

EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/preflight.sh" run-1 main >/dev/null
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" append run-1 "focused tests passed"
if grep -q "focused tests passed" "$REPO/.codex/execute-task-runs/run-1.md"; then
  echo "PASS append"
else
  echo "FAIL append"
  failures=1
fi

before="$(wc -l < "$REPO/.codex/execute-task-runs/run-1.md")"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPTS/journal.sh" append run-1 >/dev/null 2>&1
rc=$?
after="$(wc -l < "$REPO/.codex/execute-task-runs/run-1.md")"
if [ "$rc" -eq 1 ] && [ "$before" = "$after" ]; then
  echo "PASS empty append rejected"
else
  echo "FAIL empty append rejected"
  failures=1
fi

rm -rf "$REPO"
exit "$failures"
