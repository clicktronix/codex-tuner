#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

copy_fixture() {
  local destination="$1"
  mkdir -p "$destination"
  cp -R "$ROOT/.agents" "$ROOT/plugins" "$destination/"
  cp "$ROOT/.release-please-manifest.json" "$ROOT/CHANGELOG.md" \
    "$ROOT/release-please-config.json" "$destination/"
}

expect_failure() {
  local fixture="$1"
  local expected="$2"
  local output
  if output="$(python3 "$ROOT/tests/validate_structure.py" "$fixture" 2>&1)"; then
    echo "FAIL structure mutation unexpectedly passed: $expected" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) ;;
    *)
      echo "FAIL structure mutation returned the wrong error: $output" >&2
      exit 1
      ;;
  esac
}

fixture="$TMP_ROOT/valid-dependencies"
copy_fixture "$fixture"
printf '\ndependencies:\n  tools:\n    - type: "mcp"\n      value: "github"\n      description: "GitHub MCP server"\n      transport: "streamable_http"\n      url: "https://api.githubcopilot.com/mcp/"\n' >> \
  "$fixture/plugins/codex-tuner/skills/task-flow/agents/openai.yaml"
python3 "$ROOT/tests/validate_structure.py" "$fixture" >/dev/null

fixture="$TMP_ROOT/long-subtitle"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "plugins/codex-tuner/.codex-plugin/plugin.json"
payload = json.loads(path.read_text())
payload["interface"]["shortDescription"] = "x" * 31
path.write_text(json.dumps(payload))
PY
expect_failure "$fixture" "interface.shortDescription"

fixture="$TMP_ROOT/missing-logo"
copy_fixture "$fixture"
rm "$fixture/plugins/codex-tuner/assets/logo.svg"
expect_failure "$fixture" "interface.logo must reference a regular file"

fixture="$TMP_ROOT/non-square-icon"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "plugins/codex-tuner/assets/composer-icon.svg"
path.write_text(path.read_text().replace('viewBox="0 0 64 64"', 'viewBox="0 0 64 48"'))
PY
expect_failure "$fixture" "interface.composerIcon must be square"

fixture="$TMP_ROOT/symlink-logo"
copy_fixture "$fixture"
rm "$fixture/plugins/codex-tuner/assets/logo.svg"
ln -s "$ROOT/README.md" "$fixture/plugins/codex-tuner/assets/logo.svg"
expect_failure "$fixture" "interface.logo must reference a regular file"

fixture="$TMP_ROOT/chat-scope"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "plugins/codex-tuner/skills/run/agents/openai.yaml"
path.write_text(path.read_text().replace('- "CODEX"', '- "CHAT"'))
PY
expect_failure "$fixture" "run must be scoped to the CODEX product"

fixture="$TMP_ROOT/extra-skill-directory"
copy_fixture "$fixture"
mkdir "$fixture/plugins/codex-tuner/skills/not-a-skill"
expect_failure "$fixture" "skill set mismatch"

fixture="$TMP_ROOT/wrong-plugin-name"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "plugins/codex-tuner/.codex-plugin/plugin.json"
payload = json.loads(path.read_text())
payload["name"] = "different-plugin"
path.write_text(json.dumps(payload))
PY
expect_failure "$fixture" "plugin name must be codex-tuner"

fixture="$TMP_ROOT/weak-brand-color"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "plugins/codex-tuner/.codex-plugin/plugin.json"
payload = json.loads(path.read_text())
payload["interface"]["brandColor"] = "#FFFFFF"
path.write_text(json.dumps(payload))
PY
expect_failure "$fixture" "interface.brandColor must have 2:1 contrast"

echo "PASS structure mutations"
