#!/usr/bin/env bash
# Verify companion skills/plugins required by spec and run.
# CODEX_TUNER_SKILLS_ROOTS, CODEX_TUNER_PLUGIN_LIST_FILE, and
# CODEX_TUNER_CLAUDE_BIN and CODEX_TUNER_CLAUDE_AUTH_FILE are test overrides.
set -u

missing=0

if [ -n "${CODEX_TUNER_SKILLS_ROOTS:-}" ]; then
  IFS=':' read -r -a skill_roots <<< "$CODEX_TUNER_SKILLS_ROOTS"
else
  codex_data_dir="${CODEX_HOME:-$HOME/.codex}"
  skill_roots=("$codex_data_dir/skills" "$HOME/.agents/skills")
  if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    search_dir="$(pwd -P)"
    case "$search_dir/" in
      "$repo_root/"*) ;;
      *) search_dir="$repo_root" ;;
    esac
    while true; do
      skill_roots+=("$search_dir/.agents/skills")
      [ "$search_dir" = "$repo_root" ] && break
      search_dir="$(dirname "$search_dir")"
    done
    skill_roots+=("$repo_root/.codex/skills")
  fi
fi

have_skill() {
  local skill="$1"
  local root
  for root in "${skill_roots[@]}"; do
    if [ -f "$root/$skill/SKILL.md" ]; then
      return 0
    fi
  done
  return 1
}

for skill in grilling domain-modeling code-review; do
  if ! have_skill "$skill"; then
    echo "MISSING: Matt Pocock skill '$skill'" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "  install: npx skills@latest add mattpocock/skills --global --agent codex --skill grilling domain-modeling code-review --yes" >&2
fi

plugin_list() {
  if [ -n "${CODEX_TUNER_PLUGIN_LIST_FILE:-}" ]; then
    cat -- "$CODEX_TUNER_PLUGIN_LIST_FILE"
  elif command -v codex >/dev/null 2>&1; then
    codex plugin list --json 2>/dev/null
  else
    return 1
  fi
}

python_available=false
if ! command -v python3 >/dev/null 2>&1; then
  echo "MISSING: python3 (required by codex-cc-triage)" >&2
  missing=1
else
  python_available=true
fi

if [ "$python_available" = true ] && ! plugin_list | python3 -c '
import json
import sys

try:
    plugins = json.load(sys.stdin).get("installed", [])
except (AttributeError, json.JSONDecodeError):
    raise SystemExit(1)

raise SystemExit(
    0
    if any(
        plugin.get("pluginId") == "codex-cc-triage@codex-cc-triage"
        and plugin.get("installed") is True
        and plugin.get("enabled") is True
        for plugin in plugins
    )
    else 1
)
'; then
  echo "MISSING: enabled codex-cc-triage plugin (skill: claude-review)" >&2
  echo "  install: codex plugin marketplace add clicktronix/codex-cc-triage --ref main" >&2
  echo "           codex plugin add codex-cc-triage@codex-cc-triage" >&2
  missing=1
fi

claude_bin="${CODEX_TUNER_CLAUDE_BIN:-claude}"
if [[ "$claude_bin" == */* ]]; then
  claude_available=false
  [ -x "$claude_bin" ] && claude_available=true
elif command -v "$claude_bin" >/dev/null 2>&1; then
  claude_available=true
else
  claude_available=false
fi
if [ "$claude_available" != true ]; then
  echo "MISSING: Claude Code executable '$claude_bin' (required by claude-review)" >&2
  echo "  install/authenticate Claude Code, then retry in a new Codex thread" >&2
  missing=1
fi

claude_auth_status() {
  if [ -n "${CODEX_TUNER_CLAUDE_AUTH_FILE:-}" ]; then
    cat -- "$CODEX_TUNER_CLAUDE_AUTH_FILE"
  else
    "$claude_bin" auth status --json 2>/dev/null
  fi
}

if [ "$claude_available" = true ] && [ "$python_available" = true ] &&
  ! claude_auth_status | python3 -c '
import json
import sys

try:
    status = json.load(sys.stdin)
except json.JSONDecodeError:
    raise SystemExit(1)

raise SystemExit(0 if isinstance(status, dict) and status.get("loggedIn") is True else 1)
'; then
  echo "MISSING: authenticated Claude Code session (run: $claude_bin auth login)" >&2
  missing=1
fi

if [ "$missing" -eq 0 ]; then
  echo "prereqs OK"
else
  exit 1
fi
