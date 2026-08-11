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
  case "$value" in [abcdefghijklmnopqrstuvwxyz0123456789]*) ;; *) execute_task_die "run-id must start with a lowercase ASCII letter or digit" ;; esac
  case "$value" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*) execute_task_die "run-id may contain only lowercase ASCII letters, digits, dot, underscore, and hyphen" ;;
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

# BSD and GNU stat use different flags. Accept only a numeric link count.
execute_task_link_count() {
  local path="$1" links
  links="$(stat -c %h "$path" 2>/dev/null || true)"
  case "$links" in ''|*[!0-9]*) links="$(stat -f %l "$path" 2>/dev/null || true)" ;; esac
  case "$links" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$links"
}

execute_task_assert_single_link() {
  local path="$1" label="$2" links
  [ ! -e "$path" ] && [ ! -L "$path" ] && return 0
  links="$(execute_task_link_count "$path" 2>/dev/null || true)"
  [ "$links" = "1" ] || execute_task_die "$label must have exactly one link: $path"
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

execute_task_validate_item_id() {
  local kind="$1" value="$2"
  [ -n "$value" ] || execute_task_die "$kind is required"
  [ "${#value}" -le 120 ] || execute_task_die "$kind exceeds 120 characters"
  case "$value" in
    [abcdefghijklmnopqrstuvwxyz0123456789]*) ;;
    *) execute_task_die "$kind must start with a lowercase ASCII letter or digit" ;;
  esac
  case "$value" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*)
      execute_task_die "$kind may contain only lowercase ASCII letters, digits, dot, underscore, and hyphen"
      ;;
  esac
}

execute_task_current_sha() {
  git rev-parse --verify HEAD 2>/dev/null \
    || execute_task_die "run requires an existing HEAD commit"
}

execute_task_current_tree_sha() {
  git rev-parse --verify HEAD^{tree} 2>/dev/null \
    || execute_task_die "cannot resolve the current tree SHA"
}

execute_task_assert_clean_tree() {
  local dirty
  dirty="$(git status --porcelain -uall 2>/dev/null)" \
    || execute_task_die "git status failed; refusing to assume a clean tree"
  [ -z "$dirty" ] || execute_task_die "working tree must be clean for an immutable candidate"
}

# Free-form commit and PR text belongs outside the candidate. Repository identity participates in
# the namespace so two repositories may safely use the same run id.
execute_task_prepared_dir() {
  local scratch scratch_real repository_id uid prepared
  scratch="${TMPDIR:-/tmp}"
  [ -d "$scratch" ] \
    || { echo "execute-task: TMPDIR is not an existing directory: $scratch" >&2; return 1; }
  scratch_real="$(CDPATH='' cd -- "$scratch" 2>/dev/null && pwd -P)" \
    || { echo "execute-task: cannot canonicalize TMPDIR: $scratch" >&2; return 1; }
  repository_id="$(printf '%s\n' "$EXECUTE_TASK_ROOT" | git hash-object --stdin 2>/dev/null)"
  case "$repository_id" in
    ''|*[!0-9a-f]*) echo "execute-task: cannot derive prepared-file repository identity" >&2; return 1 ;;
  esac
  uid="$(id -u 2>/dev/null)"
  case "$uid" in ''|*[!0-9]*) echo "execute-task: cannot resolve current user id" >&2; return 1 ;; esac
  prepared="$scratch_real/codex-tuner-prepared-$uid/$repository_id/$EXECUTE_TASK_RUN_ID"
  case "$prepared" in
    "$EXECUTE_TASK_ROOT"|"$EXECUTE_TASK_ROOT"/*)
      echo "execute-task: prepared files must live outside the repository; TMPDIR resolves inside it" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$prepared"
}

execute_task_validate_prepared_dir() {
  local prepared="$1" repository_id uid suffix
  case "$prepared" in /*) ;; *) execute_task_die "prepared-file directory must be absolute" ;; esac
  repository_id="$(printf '%s\n' "$EXECUTE_TASK_ROOT" | git hash-object --stdin 2>/dev/null)"
  case "$repository_id" in
    ''|*[!0-9a-f]*) execute_task_die "cannot derive prepared-file repository identity" ;;
  esac
  uid="$(id -u 2>/dev/null)"
  case "$uid" in ''|*[!0-9]*) execute_task_die "cannot resolve current user id" ;; esac
  suffix="/codex-tuner-prepared-$uid/$repository_id/$EXECUTE_TASK_RUN_ID"
  case "$prepared" in *"$suffix") ;; *) execute_task_die "prepared-file directory has the wrong run identity" ;; esac
  case "$prepared" in
    "$EXECUTE_TASK_ROOT"|"$EXECUTE_TASK_ROOT"/*)
      execute_task_die "prepared files must live outside the repository"
      ;;
  esac
}

# The installed-plugin registry is the Codex authority for which reviewer version is enabled.
execute_task_claude_root_qualifies() {
  local root="$1" root_real skill="$1/skills/claude-review/SKILL.md" state="$1/scripts/review-state.sh"
  [ ! -L "$root" ] && [ -d "$root" ] || return 1
  root_real="$(CDPATH='' cd -- "$root" 2>/dev/null && pwd -P)" || return 1
  [ "$root_real" = "$root" ] || return 1
  [ ! -L "$skill" ] && [ -f "$skill" ] \
    && [ ! -L "$state" ] && [ -f "$state" ] && [ -x "$state" ] \
    && grep -qF -- '--required' "$skill" \
    && grep -qF -- 'CODEX_CC_REQUIRED_REVIEW APPROVE' "$skill" \
    && grep -qF -- 'CODEX_CC_REQUIRED_REVIEW APPROVE' "$state"
}

execute_task_claude_plugin_root() {
  local registry roots root selected="" count=0
  command -v codex >/dev/null 2>&1 || return 1
  registry="$(codex plugin list --json 2>/dev/null)" || return 1
  roots="$(printf '%s\n' "$registry" | jq -r '
    .installed
    | select(type == "array")
    | .[]
    | select(.pluginId == "codex-cc-triage@codex-cc-triage" and
             .installed == true and .enabled == true and
             (.source.path | type == "string") and (.source.path | length > 0))
    | .source.path
  ' 2>/dev/null)" || return 1
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if execute_task_claude_root_qualifies "$root"; then
      count=$((count + 1))
      selected="$root"
    fi
  done <<EOF
$roots
EOF
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$selected"
}

# Build the tree represented by the complete working tree without touching the
# user's index. The testing gate can therefore bind to the later candidate.
execute_task_worktree_tree_sha() {
  local real_index temporary_index tree
  real_index="$(git rev-parse --git-path index 2>/dev/null)" \
    || execute_task_die "cannot resolve Git index"
  temporary_index="$(mktemp "${TMPDIR:-/tmp}/codex-tuner-index.XXXXXX")" \
    || execute_task_die "cannot create temporary Git index"
  if [ -f "$real_index" ]; then
    cp "$real_index" "$temporary_index" || {
      rm -f "$temporary_index"
      execute_task_die "cannot copy Git index"
    }
  else
    rm -f "$temporary_index"
    GIT_INDEX_FILE="$temporary_index" git read-tree HEAD >/dev/null 2>&1 || {
      rm -f "$temporary_index"
      execute_task_die "cannot initialize temporary Git index"
    }
  fi
  GIT_INDEX_FILE="$temporary_index" git add -A -- :/ >/dev/null 2>&1 || {
    rm -f "$temporary_index"
    execute_task_die "cannot snapshot working tree"
  }
  tree="$(GIT_INDEX_FILE="$temporary_index" git write-tree 2>/dev/null)" || {
    rm -f "$temporary_index"
    execute_task_die "cannot write working-tree snapshot"
  }
  rm -f "$temporary_index"
  printf '%s\n' "$tree"
}
