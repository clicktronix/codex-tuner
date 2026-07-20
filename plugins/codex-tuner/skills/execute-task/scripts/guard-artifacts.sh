#!/usr/bin/env bash
# Refuse outward-facing actions when local execute-task artifacts entered Git.
# Usage: guard-artifacts.sh <run-id>
set -u
umask 077

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
execute_task_init_root

RAW="${1:-}"
execute_task_validate_run_id "$RAW"
execute_task_prepare_state allow-tracked
META="$EXECUTE_TASK_RUNS_DIR/$EXECUTE_TASK_RUN_ID.meta"
execute_task_assert_regular_or_missing "$META"
[ -f "$META" ] || execute_task_die "metadata not found for run '$EXECUTE_TASK_RUN_ID'"
ANCHOR="$(awk -F= '$1 == "target_sha" {print substr($0, index($0, "=") + 1); exit}' "$META")"
[ -n "$ANCHOR" ] || execute_task_die "target SHA missing for run '$EXECUTE_TASK_RUN_ID'"
if [ "$ANCHOR" != "(unborn)" ]; then
  case "$ANCHOR" in
    *[!0-9A-Fa-f]*) execute_task_die "invalid stored target SHA for run '$EXECUTE_TASK_RUN_ID'" ;;
  esac
  case "${#ANCHOR}" in
    40|64) ;;
    *) execute_task_die "invalid stored target SHA for run '$EXECUTE_TASK_RUN_ID'" ;;
  esac
fi

STAGED="$(git diff --cached --name-only -- "$EXECUTE_TASK_STATE_REL" "$EXECUTE_TASK_LEGACY_RUNS_REL" 2>/dev/null)" \
  || { echo "execute-task: staged diff query failed" >&2; exit 1; }
TRACKED="$(git ls-files -- "$EXECUTE_TASK_STATE_REL" "$EXECUTE_TASK_LEGACY_RUNS_REL" 2>/dev/null)" \
  || { echo "execute-task: tracked-files query failed" >&2; exit 1; }
HISTORY=""

if [ "$ANCHOR" = "(unborn)" ]; then
  if git rev-parse --verify -q 'HEAD^{commit}' >/dev/null 2>&1; then
    HISTORY="$(git log --format='%h %s' HEAD -- "$EXECUTE_TASK_STATE_REL" "$EXECUTE_TASK_LEGACY_RUNS_REL" 2>/dev/null)" \
      || { echo "execute-task: history query failed" >&2; exit 1; }
  fi
else
  git rev-parse --verify -q "$ANCHOR^{commit}" >/dev/null 2>&1 \
    || { echo "execute-task: stored target SHA '$ANCHOR' is unavailable" >&2; exit 1; }
  HISTORY="$(git log --format='%h %s' "$ANCHOR..HEAD" -- "$EXECUTE_TASK_STATE_REL" "$EXECUTE_TASK_LEGACY_RUNS_REL" 2>/dev/null)" \
    || { echo "execute-task: history query failed" >&2; exit 1; }
fi

if [ -n "$STAGED" ] || [ -n "$TRACKED" ] || [ -n "$HISTORY" ]; then
  echo "REFUSE: local execute-task artifacts are staged, tracked, or present in branch history" >&2
  printf '%s\n' "$STAGED" "$TRACKED" "$HISTORY" | awk 'NF' | sort -u >&2
  exit 3
fi

echo "== change set before outward-facing action =="
git status --porcelain -uall
