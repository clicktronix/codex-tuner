#!/usr/bin/env bash
# Scaffold optional .codex/execute-task.md defaults.
# Usage: config-init.sh <template-path>
set -u
umask 077

ROOT="${EXECUTE_TASK_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$ROOT" ] || { echo "execute-task: run inside a Git repository" >&2; exit 1; }
cd "$ROOT" 2>/dev/null || { echo "execute-task: cannot enter '$ROOT'" >&2; exit 1; }
TEMPLATE="${1:?usage: config-init.sh <template-path>}"
CONFIG=".codex/execute-task.md"
if [ -L .codex ]; then
  echo "execute-task: refusing symlinked .codex directory" >&2
  exit 1
fi
if [ -e .codex ] && [ ! -d .codex ]; then
  echo "execute-task: .codex exists but is not a directory" >&2
  exit 1
fi
if [ -L "$CONFIG" ]; then
  echo "execute-task: refusing symlinked config: $CONFIG" >&2
  exit 1
fi
if [ -f "$CONFIG" ]; then
  echo "config exists: $CONFIG"
  exit 0
fi
if [ -e "$CONFIG" ]; then
  echo "execute-task: config exists but is not a regular file: $CONFIG" >&2
  exit 1
fi
[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 1; }
mkdir -p .codex || { echo "execute-task: cannot create .codex" >&2; exit 1; }
cp "$TEMPLATE" "$CONFIG" || { echo "execute-task: cannot write $CONFIG" >&2; exit 1; }
echo "config created: $CONFIG — fill stable repo defaults before running a spec"
exit 2
