#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for test_file in "$ROOT"/tests/test_*.sh; do
  bash "$test_file"
done

python3 "$ROOT/tests/validate_scenarios.py"
python3 -m json.tool "$ROOT/.agents/plugins/marketplace.json" >/dev/null
python3 -m json.tool "$ROOT/plugins/execute-task/.codex-plugin/plugin.json" >/dev/null

if rg -n '\[TODO:' "$ROOT/plugins"; then
  echo "FAIL TODO placeholder found" >&2
  exit 1
fi

echo "PASS structure"
