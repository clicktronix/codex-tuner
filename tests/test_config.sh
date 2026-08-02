#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/plugins/codex-tuner/scripts/execute-task/config-init.sh"
TEMPLATE="$ROOT/plugins/codex-tuner/assets/execute-task/config.template.md"
failures=0
REPO="$(mktemp -d)" || exit 1
(cd "$REPO" && git init -q -b main)

EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" "$TEMPLATE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'cheap_gate' "$REPO/.codex/execute-task.md" \
  && ! find "$REPO/.codex" -name '.execute-task.*' -print -quit | grep -q .; then
  echo "PASS config-created"
else
  echo "FAIL config-created (rc=$rc)"
  failures=1
fi

printf 'SENTINEL\n' > "$REPO/.codex/execute-task.md"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" "$TEMPLATE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -qxF SENTINEL "$REPO/.codex/execute-task.md"; then
  echo "PASS config-idempotent"
else
  echo "FAIL config-idempotent (rc=$rc)"
  failures=1
fi

VICTIM="$REPO/victim"
printf 'UNCHANGED\n' > "$VICTIM"
rm "$REPO/.codex/execute-task.md"
ln -s "$VICTIM" "$REPO/.codex/execute-task.md"
EXECUTE_TASK_PROJECT_DIR="$REPO" bash "$SCRIPT" "$TEMPLATE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -qxF UNCHANGED "$VICTIM"; then
  echo "PASS config-symlink-rejected"
else
  echo "FAIL config-symlink-rejected (rc=$rc)"
  failures=1
fi

REPO_SYMLINK_DIR="$(mktemp -d)" || exit 1
OUTSIDE_DIR="$(mktemp -d)" || exit 1
(cd "$REPO_SYMLINK_DIR" && git init -q -b main && ln -s "$OUTSIDE_DIR" .codex)
EXECUTE_TASK_PROJECT_DIR="$REPO_SYMLINK_DIR" bash "$SCRIPT" "$TEMPLATE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$OUTSIDE_DIR/execute-task.md" ]; then
  echo "PASS config-directory-symlink-rejected"
else
  echo "FAIL config-directory-symlink-rejected (rc=$rc)"
  failures=1
fi

rm -rf "$REPO"
rm -rf "$REPO_SYMLINK_DIR"
rm -rf "$OUTSIDE_DIR"

NOT_REPO="$(mktemp -d)" || exit 1
EXECUTE_TASK_PROJECT_DIR="$NOT_REPO" bash "$SCRIPT" "$TEMPLATE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$NOT_REPO/.codex" ]; then
  echo "PASS config-non-git-rejected"
else
  echo "FAIL config-non-git-rejected (rc=$rc)"
  failures=1
fi
rm -rf "$NOT_REPO"
exit "$failures"
