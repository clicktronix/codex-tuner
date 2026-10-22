#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/tests/test_resources.py" "$ROOT/plugins/codex-tuner/scripts/resources.py"
