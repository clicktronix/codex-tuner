#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/plugins/codex-tuner/scripts/execute-task/prereq-check.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

skills_root="$TMP_ROOT/skills"
plugins_file="$TMP_ROOT/plugins.json"
claude_auth_file="$TMP_ROOT/claude-auth.json"
mkdir -p "$skills_root"

write_plugin_state() {
  local enabled="$1"
  printf '{"installed":[{"pluginId":"codex-cc-triage@codex-cc-triage","installed":true,"enabled":%s}]}' \
    "$enabled" > "$plugins_file"
}

write_claude_auth_state() {
  local logged_in="$1"
  printf '{"loggedIn":%s}' "$logged_in" > "$claude_auth_file"
}

expect_failure() {
  local expected="$1"
  local output
  if output="$(CODEX_TUNER_SKILLS_ROOTS="$skills_root" \
    CODEX_TUNER_PLUGIN_LIST_FILE="$plugins_file" CODEX_TUNER_CLAUDE_BIN=true \
    CODEX_TUNER_CLAUDE_AUTH_FILE="$claude_auth_file" \
    bash "$CHECK" 2>&1)"; then
    echo "FAIL prereq unexpectedly passed: $expected" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) ;;
    *)
      echo "FAIL prereq returned the wrong error: $output" >&2
      exit 1
      ;;
  esac
}

write_plugin_state true
write_claude_auth_state true
expect_failure "Matt Pocock skill 'grilling'"

for skill in grilling domain-modeling code-review; do
  mkdir -p "$skills_root/$skill"
  printf '%s\n' '---' "name: $skill" 'description: fixture' '---' > "$skills_root/$skill/SKILL.md"
done

for skill in grilling domain-modeling code-review; do
  mv "$skills_root/$skill/SKILL.md" "$skills_root/$skill/SKILL.md.hidden"
  expect_failure "Matt Pocock skill '$skill'"
  mv "$skills_root/$skill/SKILL.md.hidden" "$skills_root/$skill/SKILL.md"
done

write_plugin_state false
expect_failure "enabled codex-cc-triage plugin"

printf '{' > "$plugins_file"
expect_failure "enabled codex-cc-triage plugin"

write_plugin_state true
result="$(CODEX_TUNER_SKILLS_ROOTS="$skills_root" \
  CODEX_TUNER_PLUGIN_LIST_FILE="$plugins_file" CODEX_TUNER_CLAUDE_BIN=true \
  CODEX_TUNER_CLAUDE_AUTH_FILE="$claude_auth_file" \
  bash "$CHECK")"
[ "$result" = "prereqs OK" ] || {
  echo "FAIL prereq success output: $result" >&2
  exit 1
}

alternate_root="$TMP_ROOT/alternate-skills"
mkdir -p "$alternate_root"
cp -R "$skills_root"/. "$alternate_root"/
result="$(CODEX_TUNER_SKILLS_ROOTS="$TMP_ROOT/empty-skills:$alternate_root" \
  CODEX_TUNER_PLUGIN_LIST_FILE="$plugins_file" CODEX_TUNER_CLAUDE_BIN=true \
  CODEX_TUNER_CLAUDE_AUTH_FILE="$claude_auth_file" \
  bash "$CHECK")"
[ "$result" = "prereqs OK" ] || {
  echo "FAIL prereq did not scan all configured skill roots: $result" >&2
  exit 1
}

write_claude_auth_state false
expect_failure "authenticated Claude Code session"
write_claude_auth_state true

if output="$(CODEX_TUNER_SKILLS_ROOTS="$skills_root" \
  CODEX_TUNER_PLUGIN_LIST_FILE="$plugins_file" CODEX_TUNER_CLAUDE_BIN="$TMP_ROOT/missing-claude" \
  CODEX_TUNER_CLAUDE_AUTH_FILE="$claude_auth_file" \
  bash "$CHECK" 2>&1)"; then
  echo "FAIL prereq unexpectedly accepted a missing Claude executable" >&2
  exit 1
fi
case "$output" in
  *"Claude Code executable"*) ;;
  *)
    echo "FAIL prereq missing Claude diagnostic: $output" >&2
    exit 1
    ;;
esac

echo "PASS prereqs"
