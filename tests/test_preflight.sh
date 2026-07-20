#!/usr/bin/env bash
set -u

SCRIPT="$(cd "$(dirname "$0")/../plugins/codex-tuner/skills/execute-task/scripts" && pwd)/preflight.sh"
STATE_REL=".agent-state/codex-tuner"
failures=0

make_repo() {
  REPO="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q && git checkout -qb main && git config user.email test@example.com \
      && git config user.name test && echo base > file.txt && git add file.txt \
      && git commit -qm init
  ) || exit 1
}

make_repo
EXCLUDE_BEFORE="$(cat "$REPO/.git/info/exclude" 2>/dev/null || true)"
JOURNAL="$(EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" run-1 main)"
if [ -f "$REPO/$JOURNAL" ] \
  && [ -f "$REPO/$STATE_REL/execute-task-runs/run-1.meta" ] \
  && (cd "$REPO" && git check-ignore -q "$JOURNAL") \
  && [ "$(cat "$REPO/.git/info/exclude" 2>/dev/null || true)" = "$EXCLUDE_BEFORE" ]; then
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
if [ "$rc" -eq 0 ] && grep -q "baseline worktree: dirty" "$REPO/$STATE_REL/execute-task-runs/run-dirty.md"; then
  echo "PASS dirty baseline preserved"
else
  echo "FAIL dirty baseline preserved (rc=$rc)"
  failures=1
fi
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" run-strict --require-clean >/dev/null 2>&1
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

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" 'same/id' main >/dev/null 2>&1
slash_rc=$?
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" 'same-id' main >/dev/null 2>&1
plain_rc=$?
if [ "$slash_rc" -eq 1 ] && [ "$plain_rc" -eq 0 ] \
  && [ -f "$REPO/$STATE_REL/execute-task-runs/same-id.md" ]; then
  echo "PASS colliding run-id rejected"
else
  echo "FAIL colliding run-id rejected (slash=$slash_rc, plain=$plain_rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
TARGET_SHA="$(git -C "$REPO" rev-parse HEAD)"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" pinned main >/dev/null
if grep -qx "target_sha=$TARGET_SHA" "$REPO/$STATE_REL/execute-task-runs/pinned.meta"; then
  echo "PASS target ref pinned to commit"
else
  echo "FAIL target ref pinned to commit"
  failures=1
fi
rm -rf "$REPO"

make_repo
OUTSIDE="$(mktemp -d)"
ln -s "$OUTSIDE" "$REPO/.agent-state"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" symlink main >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$OUTSIDE/codex-tuner/execute-task-runs/symlink.md" ]; then
  echo "PASS symlinked state rejected"
else
  echo "FAIL symlinked state rejected (rc=$rc)"
  failures=1
fi
rm -rf "$REPO" "$OUTSIDE"

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" seed main >/dev/null
OUTSIDE_FILE="$(mktemp)"
printf 'outside-safe\n' > "$OUTSIDE_FILE"
ln -s "$OUTSIDE_FILE" "$REPO/$STATE_REL/execute-task-runs/file-link.md"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" file-link main >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && [ "$(cat "$OUTSIDE_FILE")" = "outside-safe" ]; then
  echo "PASS symlinked journal file rejected"
else
  echo "FAIL symlinked journal file rejected (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"
rm -f "$OUTSIDE_FILE"

exit "$failures"
