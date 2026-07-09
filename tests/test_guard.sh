#!/usr/bin/env bash
set -u

SCRIPT="$(cd "$(dirname "$0")/../plugins/execute-task/skills/execute-task/scripts" && pwd)/guard-artifacts.sh"
failures=0

make_repo() {
  REPO="$(mktemp -d)" || exit 1
  (
    cd "$REPO" && git init -q && git config user.email test@example.com \
      && git config user.name test && echo base > file.txt && git add file.txt \
      && git commit -qm init && mkdir -p .codex/execute-task-runs \
      && echo journal > .codex/execute-task-runs/run.md
  ) || exit 1
}

make_repo
(cd "$REPO" && git add -f .codex/execute-task-runs/run.md)
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "PASS staged artifact refused"
else
  echo "FAIL staged artifact refused (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
BASE="$(cd "$REPO" && git rev-parse HEAD)"
(
  cd "$REPO" && git add -f .codex/execute-task-runs/run.md \
    && git commit -qm "add local artifact" \
    && git rm -q .codex/execute-task-runs/run.md \
    && git commit -qm "remove local artifact"
)
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" "$BASE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  echo "PASS history artifact refused"
else
  echo "FAIL history artifact refused (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

make_repo
echo change >> "$REPO/file.txt"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "PASS normal change allowed"
else
  echo "FAIL normal change allowed (rc=$rc)"
  failures=1
fi
rm -rf "$REPO"

exit "$failures"
