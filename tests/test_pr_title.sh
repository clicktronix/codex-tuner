#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tests/check_pr_title.sh"
failures=0

for title in \
  "feat: harden run lifecycle" \
  "fix(run): reject stale CI" \
  "feat!: change the state contract" \
  "chore(main): release 0.4.0"; do
  if ! bash "$CHECK" "$title" >/dev/null; then
    echo "FAIL conventional title rejected: $title"
    failures=1
  fi
done

for title in \
  "Enforce the run lifecycle" \
  "feature: wrong type" \
  "fix missing colon" \
  "fix: "; do
  if bash "$CHECK" "$title" >/dev/null 2>&1; then
    echo "FAIL non-conventional title accepted: $title"
    failures=1
  fi
done

[ "$failures" -eq 0 ] && echo "PASS conventional-pr-title"
exit "$failures"
