#!/usr/bin/env bash
# Verify the installed companion's approval for this exact candidate.
set -eu
[ "$#" -eq 4 ] || { echo "usage: check-review.sh THREAD HEAD BASE SPEC" >&2; exit 1; }
THREAD="$1"; SHA="$2"; BASE="$3"; SPEC="$4"
ROOT="$(git rev-parse --show-toplevel)"
TREE="$(git rev-parse 'HEAD^{tree}')"
[ "$(git rev-parse HEAD)" = "$SHA" ] || { echo "wrong candidate worktree" >&2; exit 1; }
die() { printf 'codex-tuner review: %s\n' "$1" >&2; exit 1; }
REVIEWER_ROOT=""
REGISTRY="$(codex plugin list --json 2>/dev/null)" \
  || die "cannot read the Codex plugin registry"
ENTRY="$(jq -ce '
  [.installed[]? | select(.pluginId == "codex-cc-triage@codex-cc-triage" and
                           .installed == true and .enabled == true)]
  | if length == 1 then .[0] else error("expected one enabled companion") end' <<< "$REGISTRY")" \
  || die "expected one enabled codex-cc-triage installation"
SOURCE="$(jq -r '.source.path // ""' <<< "$ENTRY")"
VERSION="$(jq -r '.version // ""' <<< "$ENTRY")"
matches_install() {
  local path="$1"
  [[ "$path" = /* ]] && [ ! -L "$path" ] && [ -f "$path/scripts/review-state.sh" ] && \
    jq -e --arg version "$VERSION" '.name == "codex-cc-triage" and
      ($version == "" or .version == $version)' "$path/.codex-plugin/plugin.json" >/dev/null 2>&1
}
# A marketplace checkout can move independently of the installed version. Prefer
# the host's installed copy and accept a matching registry source for local installs.
if [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
  CACHE="${CODEX_HOME:-$HOME/.codex}/plugins/cache/codex-cc-triage/codex-cc-triage/$VERSION"
  if matches_install "$CACHE"; then REVIEWER_ROOT="$CACHE"; fi
fi
if [ -z "$REVIEWER_ROOT" ] && matches_install "$SOURCE"; then REVIEWER_ROOT="$SOURCE"; fi
[ -n "$REVIEWER_ROOT" ] || die "installed companion version ${VERSION:-unknown} does not match an available plugin manifest"
MARKER="$(env -u CODEX_CC_TRIAGE_STATE_DIR -u CODEX_CC_TRIAGE_PYTHON_BIN \
  CODEX_CC_TRIAGE_PROJECT_DIR="$ROOT" \
  bash "$REVIEWER_ROOT/scripts/review-state.sh" check "$THREAD")" \
  || die "codex-cc-triage did not approve thread '$THREAD': $MARKER"
prefix="CODEX_CC_REQUIRED_REVIEW APPROVE thread=$THREAD head=$SHA tree=$TREE fingerprint="
suffix=" base_sha=$BASE spec_path=$SPEC"
fingerprint="${MARKER#"$prefix"}"; fingerprint="${fingerprint%"$suffix"}"
[[ "$fingerprint" =~ ^[a-f0-9]{64}$ ]] && [ "$MARKER" = "$prefix$fingerprint$suffix" ] \
  || die "codex-cc-triage marker does not cover thread, candidate, and spec"
printf '%s\n' "$MARKER"
