#!/usr/bin/env bash
set -u

SCRIPTS="$(cd "$(dirname "$0")/../plugins/codex-tuner/skills/execute-task/scripts" && pwd)"
SCRIPT="$SCRIPTS/guard-artifacts.sh"
PREFLIGHT="$SCRIPTS/preflight.sh"
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
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$PREFLIGHT" staged main >/dev/null
(cd "$REPO" && git add -f "$STATE_REL/execute-task-runs/staged.md")
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" staged >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "PASS staged artifact refused"
else
  echo "FAIL staged artifact refused (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$PREFLIGHT" history main >/dev/null
(
  cd "$REPO" && git add -f "$STATE_REL/execute-task-runs/history.md" \
    && git commit -qm "add local artifact" \
    && git rm -q "$STATE_REL/execute-task-runs/history.md" \
    && git commit -qm "remove local artifact"
)
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" history >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "PASS history artifact refused"
else
  echo "FAIL history artifact refused (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$PREFLIGHT" normal main >/dev/null
echo change >> "$REPO/file.txt"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" normal >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "PASS normal change allowed"
else
  echo "FAIL normal change allowed (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$PREFLIGHT" tracked-ignore main >/dev/null
printf 'keep-this-content\n' > "$REPO/$STATE_REL/.gitignore"
(cd "$REPO" && git add -f "$STATE_REL/.gitignore")
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" tracked-ignore >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ] \
  && grep -qxF 'keep-this-content' "$REPO/$STATE_REL/.gitignore"; then
  echo "PASS tracked state refused without mutation"
else
  echo "FAIL tracked state refused without mutation (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

exit "$failures"
