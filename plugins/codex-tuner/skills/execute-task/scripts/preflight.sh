#!/usr/bin/env bash
# Prepare a resumable execute-task journal without requiring a pristine worktree.
# Usage: preflight.sh <run-id> [target-branch] [--require-clean]
set -u

ROOT="${EXECUTE_TASK_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "execute-task: cannot enter repo root '$ROOT'" >&2; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 \
  || { echo "execute-task: not a git repo at '$ROOT'" >&2; exit 1; }

RAW="${1:?usage: preflight.sh <run-id> [target-branch] [--require-clean]}"
RUN_ID="$(printf '%s' "$RAW" | tr -c 'A-Za-z0-9_.-' '-')"
case "$RUN_ID" in
  ''|.|..) echo "execute-task: invalid run-id '$RAW'" >&2; exit 1 ;;
esac
TARGET="${2:-}"
REQUIRE_CLEAN="${3:-}"
RUNS_DIR=".codex/execute-task-runs"

# Keep operational state local, including in linked worktrees and monorepo subdirectories.
if ! git check-ignore -q "$RUNS_DIR/probe" 2>/dev/null; then
  EXCLUDE_FILE="$(git rev-parse --git-path info/exclude 2>/dev/null)"
  PREFIX="$(git rev-parse --show-prefix 2>/dev/null)"
  PATTERN="/$PREFIX$RUNS_DIR/"
  [ -n "$EXCLUDE_FILE" ] \
    || { echo "execute-task: cannot resolve git exclude file" >&2; exit 1; }
  mkdir -p "$(dirname "$EXCLUDE_FILE")" \
    || { echo "execute-task: cannot create exclude directory" >&2; exit 1; }
  if ! grep -qxF "$PATTERN" "$EXCLUDE_FILE" 2>/dev/null; then
    if [ -s "$EXCLUDE_FILE" ] && [ -n "$(tail -c1 "$EXCLUDE_FILE" 2>/dev/null)" ]; then
      printf '\n' >> "$EXCLUDE_FILE"
    fi
    printf '%s\n' "$PATTERN" >> "$EXCLUDE_FILE" \
      || { echo "execute-task: cannot update $EXCLUDE_FILE" >&2; exit 1; }
  fi
fi

if ! DIRTY="$(git status --porcelain -unormal -- . ":(exclude)$RUNS_DIR" 2>/dev/null)"; then
  echo "execute-task: git status failed" >&2
  exit 1
fi
if [ "$REQUIRE_CLEAN" = "--require-clean" ] && [ -n "$DIRTY" ]; then
  echo "execute-task: dirty worktree and --require-clean was requested:" >&2
  printf '%s\n' "$DIRTY" >&2
  exit 2
fi

mkdir -p "$RUNS_DIR" || { echo "execute-task: cannot create $RUNS_DIR" >&2; exit 1; }
JOURNAL="$RUNS_DIR/$RUN_ID.md"
BASE_SHA="$(git rev-parse --verify HEAD 2>/dev/null || echo '(unborn)')"
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"

if [ -f "$JOURNAL" ]; then
  {
    echo
    echo "## restarted: $(date -u +%FT%TZ) (branch $BRANCH, base $BASE_SHA)"
  } >> "$JOURNAL" || { echo "execute-task: cannot append $JOURNAL" >&2; exit 1; }
else
  {
    echo "# execute-task run: $RUN_ID"
    echo
    echo "- started: $(date -u +%FT%TZ)"
    echo "- branch: $BRANCH"
    echo "- target: ${TARGET:-?}"
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

echo "$JOURNAL"
