#!/usr/bin/env bash
# Append a timestamped journal entry or print the journal path.
# Usage: journal.sh append|path <run-id> [text]
set -u

ROOT="${EXECUTE_TASK_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "execute-task: cannot enter repo root '$ROOT'" >&2; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 \
  || { echo "execute-task: not a git repo at '$ROOT'" >&2; exit 1; }

SUBCOMMAND="${1:?usage: journal.sh append|path <run-id> [text]}"
RAW="${2:?run-id required}"
RUN_ID="$(printf '%s' "$RAW" | tr -c 'A-Za-z0-9_.-' '-')"
case "$RUN_ID" in
  ''|.|..) echo "execute-task: invalid run-id '$RAW'" >&2; exit 1 ;;
esac
JOURNAL=".codex/execute-task-runs/$RUN_ID.md"

case "$SUBCOMMAND" in
  path)
    echo "$JOURNAL"
    ;;
  append)
    shift 2
    MESSAGE="$*"
    [ -n "$MESSAGE" ] || { echo "execute-task: journal message required" >&2; exit 1; }
    [ -f "$JOURNAL" ] \
      || { echo "execute-task: journal not found: $JOURNAL" >&2; exit 1; }
    printf -- '- [%s] %s\n' "$(date -u +%FT%TZ)" "$MESSAGE" >> "$JOURNAL"
    ;;
  *)
    echo "execute-task: unknown subcommand '$SUBCOMMAND'" >&2
    exit 1
    ;;
esac
