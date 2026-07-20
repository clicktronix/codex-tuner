#!/usr/bin/env bash
# Append a timestamped journal entry or print the journal path.
# Usage: journal.sh append|path <run-id> [text]
set -u
umask 077

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
execute_task_init_root

SUBCOMMAND="${1:-}"
RAW="${2:-}"
execute_task_validate_run_id "$RAW"
execute_task_prepare_state
JOURNAL="$EXECUTE_TASK_RUNS_DIR/$EXECUTE_TASK_RUN_ID.md"
META="$EXECUTE_TASK_RUNS_DIR/$EXECUTE_TASK_RUN_ID.meta"
execute_task_assert_regular_or_missing "$JOURNAL"
execute_task_assert_regular_or_missing "$META"

case "$SUBCOMMAND" in
  path)
    echo "$EXECUTE_TASK_RUNS_REL/$EXECUTE_TASK_RUN_ID.md"
    ;;
  append)
    shift 2
    MESSAGE="$*"
    [ -n "$MESSAGE" ] || { echo "execute-task: journal message required" >&2; exit 1; }
    [ -f "$JOURNAL" ] \
      || { echo "execute-task: journal not found: $EXECUTE_TASK_RUNS_REL/$EXECUTE_TASK_RUN_ID.md" >&2; exit 1; }
    [ -f "$META" ] \
      || { echo "execute-task: metadata not found for run '$EXECUTE_TASK_RUN_ID'" >&2; exit 1; }
    printf -- '- [%s] %s\n' "$(date -u +%FT%TZ)" "$MESSAGE" >> "$JOURNAL" \
      || execute_task_die "cannot append journal for run '$EXECUTE_TASK_RUN_ID'"
    ;;
  *)
    echo "execute-task: unknown subcommand '$SUBCOMMAND'" >&2
    exit 1
    ;;
esac
