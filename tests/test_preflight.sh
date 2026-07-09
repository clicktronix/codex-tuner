#!/usr/bin/env bash
set -u

SCRIPT="$(cd "$(dirname "$0")/../plugins/execute-task/skills/execute-task/scripts" && pwd)/preflight.sh"
failures=0

make_repo() {
  REPO="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q && git config user.email test@example.com \
      && git config user.name test && echo base > file.txt && git add file.txt \
      && git commit -qm init
  ) || exit 1
}

make_repo
JOURNAL="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" run-1 main)"
if [ -f "$REPO/$JOURNAL" ] && (cd "$REPO" && git check-ignore -q "$JOURNAL"); then
  echo "PASS clean preflight"
else
  echo "FAIL clean preflight"
  failures=1
fi
rm -rf "$REPO"

make_repo
echo user-change >> "$REPO/file.txt"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" run-dirty main >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "baseline worktree: dirty" "$REPO/.codex/execute-task-runs/run-dirty.md"; then
  echo "PASS dirty baseline preserved"
else
  echo "FAIL dirty baseline preserved (rc=$rc)"
  failures=1
fi
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" run-strict main --require-clean >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  echo "PASS require-clean blocks"
else
  echo "FAIL require-clean blocks (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" '..' main >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ]; then
  echo "PASS traversal run-id rejected"
else
  echo "FAIL traversal run-id rejected (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

exit "$failures"
