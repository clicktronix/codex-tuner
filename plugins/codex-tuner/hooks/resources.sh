#!/usr/bin/env bash
# The host passes native lifecycle JSON on stdin. No model calls and no process sweep.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/resources.py" hook
