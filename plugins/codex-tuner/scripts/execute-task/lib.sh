#!/usr/bin/env bash
# Shared state and validation helpers for codex-tuner run scripts.

EXECUTE_TASK_STATE_REL=".agent-state/codex-tuner"
EXECUTE_TASK_RUNS_REL="$EXECUTE_TASK_STATE_REL/execute-task-runs"
EXECUTE_TASK_LEGACY_RUNS_REL=".codex/execute-task-runs"

execute_task_die() {
  echo "execute-task: $*" >&2
  exit 1
}

execute_task_init_root() {
  local requested
  requested="${EXECUTE_TASK_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$requested" ] || execute_task_die "run inside a Git repository"
  cd "$requested" 2>/dev/null || execute_task_die "cannot enter repository '$requested'"
  EXECUTE_TASK_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || execute_task_die "not a Git repository: '$requested'"
  cd "$EXECUTE_TASK_ROOT" 2>/dev/null || execute_task_die "cannot enter repository root"
  EXECUTE_TASK_ROOT="$(pwd -P)" || execute_task_die "cannot canonicalize repository root"
  EXECUTE_TASK_STATE_DIR="$EXECUTE_TASK_ROOT/$EXECUTE_TASK_STATE_REL"
  EXECUTE_TASK_RUNS_DIR="$EXECUTE_TASK_ROOT/$EXECUTE_TASK_RUNS_REL"
}

execute_task_validate_run_id() {
  local value="$1"
  [ -n "$value" ] || execute_task_die "run-id is required"
  [ "${#value}" -le 80 ] || execute_task_die "run-id exceeds 80 characters"
  case "$value" in [a-z0-9]*) ;; *) execute_task_die "run-id must start with a lowercase ASCII letter or digit" ;; esac
  case "$value" in
    *[!a-z0-9._-]*) execute_task_die "run-id may contain only lowercase ASCII letters, digits, dot, underscore, and hyphen" ;;
  esac
  EXECUTE_TASK_RUN_ID="$value"
}

execute_task_prepare_state() {
  local allow_tracked="${1:-}" parent ignore_file resolved tracked temporary path
  parent="$EXECUTE_TASK_ROOT/.agent-state"
  ignore_file="$EXECUTE_TASK_STATE_DIR/.gitignore"

  for path in "$parent" "$EXECUTE_TASK_STATE_DIR" "$EXECUTE_TASK_RUNS_DIR"; do
    [ ! -L "$path" ] || execute_task_die "refusing symlinked state path: $path"
    [ ! -e "$path" ] || [ -d "$path" ] || execute_task_die "state path is not a directory: $path"
    mkdir -p "$path" || execute_task_die "cannot create state directory '$path'"
  done

  resolved="$(CDPATH='' cd -- "$EXECUTE_TASK_RUNS_DIR" 2>/dev/null && pwd -P)" \
    || execute_task_die "cannot canonicalize state directory"
  case "$resolved" in "$EXECUTE_TASK_ROOT"/*) ;; *) execute_task_die "state directory escapes repository: $resolved" ;; esac

  tracked="$(git ls-files -- "$EXECUTE_TASK_STATE_REL" 2>/dev/null)" \
    || execute_task_die "cannot inspect tracked state paths"
  if [ -n "$tracked" ] && [ "$allow_tracked" != "allow-tracked" ]; then
    execute_task_die "refusing tracked state directory: $EXECUTE_TASK_STATE_REL"
  fi
  if [ "$allow_tracked" = "allow-tracked" ]; then
    return
  fi

  [ ! -L "$ignore_file" ] || execute_task_die "refusing symlinked state ignore file"
  [ ! -e "$ignore_file" ] || [ -f "$ignore_file" ] || execute_task_die "state ignore path is not a regular file"
  if ! grep -qxF '*' "$ignore_file" 2>/dev/null; then
    temporary="$ignore_file.tmp.$$"
    printf '*\n' > "$temporary" || execute_task_die "cannot write state ignore file"
    mv "$temporary" "$ignore_file" || execute_task_die "cannot install state ignore file"
  fi
  git check-ignore -q "$EXECUTE_TASK_RUNS_REL/probe" 2>/dev/null \
    || execute_task_die "state directory is not ignored: $EXECUTE_TASK_STATE_REL"
}

execute_task_assert_regular_or_missing() {
  local path="$1"
  [ ! -L "$path" ] || execute_task_die "refusing symlinked state file: $path"
  [ ! -e "$path" ] || [ -f "$path" ] || execute_task_die "state path is not a regular file: $path"
}

execute_task_read_meta() {
  local key="$1" path="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "$path"
}

execute_task_current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || printf '%s\n' '(detached)'
}

execute_task_assert_run_owner() {
  local meta="$1" stored_run_id stored_branch current_branch
  execute_task_assert_regular_or_missing "$meta"
  [ -f "$meta" ] || execute_task_die "metadata not found for run '$EXECUTE_TASK_RUN_ID'"
  stored_run_id="$(execute_task_read_meta run_id "$meta")"
  stored_branch="$(execute_task_read_meta branch "$meta")"
  current_branch="$(execute_task_current_branch)"
  [ "$stored_run_id" = "$EXECUTE_TASK_RUN_ID" ] \
    || execute_task_die "metadata run-id '$stored_run_id' does not match '$EXECUTE_TASK_RUN_ID'"
  [ -n "$stored_branch" ] || execute_task_die "branch missing for run '$EXECUTE_TASK_RUN_ID'"
  [ "$stored_branch" = "$current_branch" ] \
    || execute_task_die "run '$EXECUTE_TASK_RUN_ID' belongs to branch '$stored_branch', not '$current_branch'"
}
