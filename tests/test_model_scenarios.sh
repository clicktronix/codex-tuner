#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$(mktemp -d)" || exit 1
trap 'rm -rf "$TOOLS"' EXIT

cat > "$TOOLS/codex" <<'CODEX_STUB'
#!/usr/bin/env bash
set -u
out=""
ephemeral=0
ignore_config=0
ignore_rules=0
read_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ephemeral) ephemeral=1 ;;
    --ignore-user-config) ignore_config=1 ;;
    --ignore-rules) ignore_rules=1 ;;
    --sandbox) [ "$2" = read-only ] && read_only=1; shift ;;
    --output-last-message) out="$2"; shift ;;
  esac
  shift
done
[ "$ephemeral:$ignore_config:$ignore_rules:$read_only" = 1:1:1:1 ] || exit 9
prompt="$(cat)"
if [ "${FAKE_BAD_MODEL_SCENARIO:-}" = 1 ]; then
  printf '%s\n' '{"decision":"parallel","first_action":"delegate_both","parallelism":"parallel","owner":"subagents","rationale":"unsafe mutation fixture"}' > "$out"
elif printf '%s' "$prompt" | grep -q 'No visible Codex plan exists yet'; then
  printf '%s\n' '{"decision":"publish_plan_before_edit","first_action":"update_plan","parallelism":"not_applicable","owner":"parent","rationale":"publish the lifecycle before mutation"}' > "$out"
else
  printf '%s\n' '{"decision":"serial","first_action":"update_plan","parallelism":"serial","owner":"parent","rationale":"publish the plan, then keep overlap and dependency parent-owned"}' > "$out"
fi
CODEX_STUB
chmod +x "$TOOLS/codex"

if CODEX_EVAL_BIN="$TOOLS/codex" python3 "$ROOT/tests/run_model_scenarios.py" >/dev/null; then
  echo "PASS model-scenario-runner"
else
  echo "FAIL model-scenario-runner"
  exit 1
fi

if FAKE_BAD_MODEL_SCENARIO=1 CODEX_EVAL_BIN="$TOOLS/codex" \
    python3 "$ROOT/tests/run_model_scenarios.py" visible-plan-before-edit >/dev/null 2>&1; then
  echo "FAIL model-scenario-runner-mutation"
  exit 1
else
  echo "PASS model-scenario-runner-mutation"
fi
