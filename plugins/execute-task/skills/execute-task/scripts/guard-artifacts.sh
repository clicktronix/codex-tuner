#!/usr/bin/env bash
# Refuse outward-facing actions when local execute-task artifacts entered Git.
# Usage: guard-artifacts.sh [target-ref]
set -u

ROOT="${EXECUTE_TASK_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "execute-task: cannot enter repo root '$ROOT'" >&2; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 \
  || { echo "execute-task: not a git repo at '$ROOT'" >&2; exit 1; }

TARGET="${1:-}"
RUNS_DIR=".codex/execute-task-runs"

STAGED="$(git diff --cached --name-only -- "$RUNS_DIR" 2>/dev/null)" \
  || { echo "execute-task: staged diff query failed" >&2; exit 1; }
TRACKED="$(git ls-files -- "$RUNS_DIR" 2>/dev/null)" \
  || { echo "execute-task: tracked-files query failed" >&2; exit 1; }
HISTORY=""

if [ -n "$TARGET" ]; then
  git rev-parse --verify -q "$TARGET^{commit}" >/dev/null 2>&1 \
    || { echo "execute-task: target '$TARGET' is not a valid ref" >&2; exit 1; }
  HISTORY="$(git log --format='%h %s' "$TARGET..HEAD" -- "$RUNS_DIR" 2>/dev/null)" \
    || { echo "execute-task: history query failed" >&2; exit 1; }
fi

if [ -n "$STAGED" ] || [ -n "$TRACKED" ] || [ -n "$HISTORY" ]; then
  echo "REFUSE: local execute-task artifacts are staged, tracked, or present in branch history" >&2
  printf '%s\n' "$STAGED" "$TRACKED" "$HISTORY" | awk 'NF' | sort -u >&2
  exit 3
fi

echo "== change set before outward-facing action =="
git status --porcelain -uall
