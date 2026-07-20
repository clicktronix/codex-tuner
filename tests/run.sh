#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for script in "$ROOT"/plugins/codex-tuner/skills/execute-task/scripts/*.sh "$ROOT"/tests/test_*.sh; do
  bash -n "$script"
done

for test_file in "$ROOT"/tests/test_*.sh; do
  bash "$test_file"
done

python3 -m py_compile "$ROOT/tests/validate_scenarios.py" "$ROOT/tests/validate_structure.py"
python3 "$ROOT/tests/validate_scenarios.py"
python3 "$ROOT/tests/validate_structure.py"
python3 -m json.tool "$ROOT/.agents/plugins/marketplace.json" >/dev/null
python3 -m json.tool "$ROOT/plugins/codex-tuner/.codex-plugin/plugin.json" >/dev/null

if rg -n '\[TODO:' "$ROOT/plugins"; then
  echo "FAIL TODO placeholder found" >&2
  exit 1
fi

echo "PASS structure"
