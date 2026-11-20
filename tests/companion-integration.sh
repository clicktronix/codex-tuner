#!/usr/bin/env bash
# bash tests/companion-integration.sh /path/to/codex-cc-triage
# Exercise both public plugins through an isolated Codex registry and an offline Claude fixture.
set -euo pipefail
tuner_repo="$(cd "$(dirname "$0")/.." && pwd)"
companion_repo="$(cd "${1:?pass the codex-cc-triage source checkout}" && pwd)"
sandbox_dir="$(mktemp -d)"
trap 'rm -rf "$sandbox_dir"' EXIT
mkdir -p "$sandbox_dir/codex" "$sandbox_dir/repo"
codex_local() { env CODEX_HOME="$sandbox_dir/codex" codex "$@"; }
for source in "$companion_repo" "$tuner_repo"; do
  codex_local plugin marketplace add "$source" >/dev/null
done
for name in codex-cc-triage codex-tuner; do
  codex_local plugin add "$name@$name" >/dev/null
done
registry="$(codex_local plugin list --json)"
scripts() {
  local name="$1" version installed_plugin
  version="$(jq -er --arg id "$name@$name" '.installed[] | select(.pluginId == $id and .enabled and .installed) | .version' <<< "$registry")"
  installed_plugin="$sandbox_dir/codex/plugins/cache/$name/$name/$version"
  jq -e --arg name "$name" --arg version "$version" '.name == $name and .version == $version' \
    "$installed_plugin/.codex-plugin/plugin.json" >/dev/null
  printf '%s/scripts\n' "$installed_plugin"
}
bridge="$(scripts codex-cc-triage)"
tuner="$(scripts codex-tuner)"
cd "$sandbox_dir/repo"
git init -qb main
git config user.name "Fixture Owner"
git config user.email fixture@example.invalid
git -c commit.gpgsign=false commit --allow-empty -qm baseline
base="$(git rev-parse HEAD)"
git checkout -qb task
spec='docs/План работ.md'
mkdir -p docs
printf '# Task\n\n## Delivery\ntarget: main\nbranch: task\nhost: local\nmerge: ff\nreview: claude\ndelivery: merge\nci: none:offline fixture\n' > "$spec"
git add -- "$spec"
git -c commit.gpgsign=false commit -qm candidate
sha="$(git rev-parse HEAD)"
export CODEX_CC_TRIAGE_CLAUDE_BIN="$companion_repo/tests/fixtures/fake-claude.sh"
export CODEX_CC_TRIAGE_PROJECT_DIR="$PWD"
export FAKE_CLAUDE_ARGS_LOG="$sandbox_dir/args" FAKE_CLAUDE_PROMPT_LOG="$sandbox_dir/prompt"
export FAKE_CLAUDE_RESULT=APPROVE
unset CODEX_CC_TRIAGE_STATE_DIR
gate="$bridge/review-state.sh"
begin="$(bash "$gate" begin bridge --base "$base" --spec "$spec")"
[[ "$begin" == *attempt=1/7* ]]
claim="${begin##* claim=}"; claim="${claim%% *}"
header="$(bash "$gate" header bridge)"
printf '%s\n%s\n' "$header" 'Review this candidate. End with APPROVE or REQUEST_CHANGES.' |
  bash "$bridge/claude-thread.sh" dispatch review bridge "$base" >/dev/null
bash "$gate" record bridge foreground "$claim" > "$sandbox_dir/round"
CODEX_HOME="$sandbox_dir/codex" bash "$tuner/check-review.sh" bridge "$sha" "$base" "$spec" > "$sandbox_dir/checked"
cmp "$sandbox_dir/round" "$sandbox_dir/checked"
local_record="$(python3 "$tuner/finish-review.py" "$sandbox_dir/checked")"
[[ "$local_record" == *"codex-tuner-verdict: APPROVE $sha"* ]]
git notes --ref=codex-tuner add -m "codex-tuner-verdict: APPROVE $sha
codex-tuner-verified: $sha
Producer and consumer agree on the candidate and full spec path.
codex-tuner-local-ci: $sha bridge integration passed" "$sha"
CODEX_HOME="$sandbox_dir/codex" python3 "$tuner/local-merge.py" --check-only "$sha" bridge "$base" "$spec"
[[ "$(git rev-parse main)" == "$base" ]]
git -c commit.gpgsign=false commit --allow-empty -qm changed
if CODEX_HOME="$sandbox_dir/codex" bash "$tuner/check-review.sh" bridge "$(git rev-parse HEAD)" "$base" "$spec"; then
  echo 'FAIL an old approval covered a different commit' >&2; exit 1
fi
[[ "$(grep -cx -- '-p' "$FAKE_CLAUDE_ARGS_LOG")" == 1 ]]
echo 'PASS cross-plugin exact-candidate handoff, stale refusal, one offline call and zero publications'
