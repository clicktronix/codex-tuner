#!/usr/bin/env bash
set -u

title="${1:-}"
[ -n "$title" ] || { echo "PR title is required" >&2; exit 1; }
printf '%s\n' "$title" \
  | grep -Eq '^(feat|fix|perf|refactor|docs|test|build|ci|chore|revert)(\([a-zA-Z0-9._/-]+\))?!?: .+' \
  || {
    echo "PR title must be a Conventional Commit subject, for example: feat: harden run lifecycle" >&2
    exit 1
  }
