#!/usr/bin/env bash
# Prepare a resumable execute-task journal without requiring a pristine worktree.
# Usage: preflight.sh <run-id> [target-ref] [--require-clean]
set -u
umask 077

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
execute_task_init_root

RAW="${1:-}"
execute_task_validate_run_id "$RAW"
shift
TARGET=""
REQUIRE_CLEAN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-clean) REQUIRE_CLEAN=1 ;;
    --*) execute_task_die "unknown option '$1'" ;;
    *)
      [ -z "$TARGET" ] || execute_task_die "multiple target refs provided"
      TARGET="$1"
      ;;
  esac
  shift
done
execute_task_prepare_state
JOURNAL="$EXECUTE_TASK_RUNS_DIR/$EXECUTE_TASK_RUN_ID.md"
META="$EXECUTE_TASK_RUNS_DIR/$EXECUTE_TASK_RUN_ID.meta"
execute_task_assert_regular_or_missing "$JOURNAL"
execute_task_assert_regular_or_missing "$META"

if ! DIRTY="$(git status --porcelain -unormal -- . ":(exclude)$EXECUTE_TASK_STATE_REL" 2>/dev/null)"; then
  echo "execute-task: git status failed" >&2
  exit 1
fi
if [ "$REQUIRE_CLEAN" -eq 1 ] && [ -n "$DIRTY" ]; then
  echo "execute-task: dirty worktree and --require-clean was requested:" >&2
  printf '%s\n' "$DIRTY" >&2
  exit 2
fi

BASE_SHA="$(git rev-parse --verify HEAD 2>/dev/null || echo '(unborn)')"
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"
TARGET_SHA="$BASE_SHA"
if [ -n "$TARGET" ]; then
  case "$TARGET" in
    -*) execute_task_die "target ref must not start with '-'" ;;
  esac
  TARGET_SHA="$(git rev-parse --verify "$TARGET^{commit}" 2>/dev/null)" \
    || execute_task_die "target '$TARGET' is not a valid commit"
fi

if [ -f "$JOURNAL" ]; then
  [ -f "$META" ] || execute_task_die "metadata missing for existing run '$EXECUTE_TASK_RUN_ID'"
  STORED_BRANCH="$(awk -F= '$1 == "branch" {print substr($0, index($0, "=") + 1); exit}' "$META")"
  STORED_TARGET="$(awk -F= '$1 == "target_ref" {print substr($0, index($0, "=") + 1); exit}' "$META")"
  [ "$STORED_BRANCH" = "$BRANCH" ] \
    || execute_task_die "run '$EXECUTE_TASK_RUN_ID' belongs to branch '$STORED_BRANCH', not '$BRANCH'"
  [ -z "$TARGET" ] || [ "$STORED_TARGET" = "$TARGET" ] \
    || execute_task_die "run '$EXECUTE_TASK_RUN_ID' targets '$STORED_TARGET', not '$TARGET'"
  {
    echo
    echo "## restarted: $(date -u +%FT%TZ) (branch $BRANCH, base $BASE_SHA)"
  } >> "$JOURNAL" || { echo "execute-task: cannot append $JOURNAL" >&2; exit 1; }
else
  [ ! -e "$META" ] || execute_task_die "metadata exists without journal for '$EXECUTE_TASK_RUN_ID'"
  META_TMP="$META.tmp.$$"
  {
    echo "version=1"
    echo "run_id=$EXECUTE_TASK_RUN_ID"
    echo "branch=$BRANCH"
    echo "base_sha=$BASE_SHA"
    echo "target_ref=$TARGET"
    echo "target_sha=$TARGET_SHA"
  } > "$META_TMP" || execute_task_die "cannot write run metadata"
  mv "$META_TMP" "$META" || execute_task_die "cannot install run metadata"
  {
    echo "# execute-task run: $EXECUTE_TASK_RUN_ID"
    echo
    echo "- started: $(date -u +%FT%TZ)"
    echo "- branch: $BRANCH"
    echo "- target: ${TARGET:-?}"
    echo "- target SHA: $TARGET_SHA"
    echo "- base SHA: $BASE_SHA"
    if [ -n "$DIRTY" ]; then
      echo "- baseline worktree: dirty (preserve unrelated changes)"
      echo
      echo "## baseline status"
      echo '```text'
      printf '%s\n' "$DIRTY"
      echo '```'
    else
      echo "- baseline worktree: clean"
    fi
    echo
    echo "## log"
  } > "$JOURNAL" || { echo "execute-task: cannot write $JOURNAL" >&2; exit 1; }
fi

echo "$EXECUTE_TASK_RUNS_REL/$EXECUTE_TASK_RUN_ID.md"
