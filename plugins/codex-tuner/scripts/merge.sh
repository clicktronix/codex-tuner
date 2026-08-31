#!/usr/bin/env bash
# Checked merge boundary for codex-tuner.
#
# merge.sh [--check-only] <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>
set -u

GH="${CODEX_TUNER_GH:-gh}"

die() { printf 'codex-tuner merge: %s\n' "$1" >&2; exit 1; }

CHECK_ONLY=""
case "${1:-}" in --check-only) CHECK_ONLY=1; shift ;; esac

PR="${1:-}"; STRATEGY="${2:-}"; SHA="${3:-}"; THREAD="${4:-}"; BASE="${5:-}"; SPEC="${6:-}"
[ -n "$PR" ] && [ -n "$STRATEGY" ] && [ -n "$SHA" ] && [ -n "$THREAD" ] \
  && [ -n "$BASE" ] && [ -n "$SPEC" ] \
  || die "usage: merge.sh [--check-only] <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>"
case "$PR" in ''|0|*[!0-9]*) die "pull request must be a positive number" ;; esac
[ "$PR" -gt 0 ] 2>/dev/null || die "pull request must be a positive number"
case "$STRATEGY" in squash|merge) ;; *) die "strategy must be squash or merge" ;; esac
case "$SPEC" in
  /*|..|../*|*/../*|*[!A-Za-z0-9_./-]*) die "spec must be a stable repository-relative path" ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a Git repository"
[ -f "$ROOT/$SPEC" ] || die "spec file not found: $SPEC"
git -C "$ROOT" ls-files --error-unmatch -- "$SPEC" >/dev/null 2>&1 \
  || die "spec must be tracked: $SPEC"
TARGET_COUNT="$(grep -Ec '^target:[[:space:]]*[^[:space:]].*$' "$ROOT/$SPEC" 2>/dev/null || true)"
[ "$TARGET_COUNT" -eq 1 ] 2>/dev/null || die "spec must declare exactly one delivery target"
SPEC_TARGET="$(sed -n 's/^target:[[:space:]]*//p' "$ROOT/$SPEC")"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || die "candidate worktree is not clean"
[ "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" = "$SHA" ] \
  || die "current HEAD is not candidate $SHA"

PRJSON="$($GH pr view "$PR" --json baseRefName,baseRefOid,headRefOid,reviews 2>/dev/null)" \
  || die "cannot resolve pull request '$PR'"
HEAD_SHA="$(printf '%s' "$PRJSON" | jq -r '.headRefOid // empty')"
BASE_REF="$(printf '%s' "$PRJSON" | jq -r '.baseRefName // empty')"
BASE_OID="$(printf '%s' "$PRJSON" | jq -r '.baseRefOid // empty')"
[ "$HEAD_SHA" = "$SHA" ] \
  || die "the head of $PR is ${HEAD_SHA:-unknown}, not candidate $SHA"
[ -n "$BASE_REF" ] && [ "$BASE_REF" = "$SPEC_TARGET" ] \
  || die "the base of $PR is ${BASE_REF:-unknown}, not spec target $SPEC_TARGET"
[ -n "$BASE_OID" ] && [ "$BASE_OID" = "$BASE" ] \
  || die "the current PR base ${BASE_OID:-unknown} is not the reviewed base $BASE"
git -C "$ROOT" merge-base --is-ancestor "$BASE" "$SHA" 2>/dev/null \
  || die "reviewed base $BASE is not an ancestor of candidate $SHA"

REVIEWER_ROOT=""
REGISTRY="$(codex plugin list --json 2>/dev/null)" \
  || die "cannot read the Codex plugin registry"
ROOTS="$(printf '%s' "$REGISTRY" | jq -r '
  .installed[]?
  | select(.pluginId == "codex-cc-triage@codex-cc-triage" and
           .installed == true and .enabled == true and
           (.source.path | type == "string"))
  | .source.path')" || die "cannot parse the Codex plugin registry"
COUNT=0
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  case "$candidate" in /*) ;; *) continue ;; esac
  [ ! -L "$candidate" ] && [ -f "$candidate/scripts/review-state.sh" ] || continue
  COUNT=$((COUNT + 1)); REVIEWER_ROOT="$candidate"
done <<EOF
$ROOTS
EOF
[ "$COUNT" -eq 1 ] \
  || die "expected one enabled codex-cc-triage installation, found $COUNT"

MARKER="$(env -u CODEX_CC_TRIAGE_STATE_DIR -u CODEX_CC_TRIAGE_PYTHON_BIN \
  CODEX_CC_TRIAGE_PROJECT_DIR="$ROOT" \
  bash "$REVIEWER_ROOT/scripts/review-state.sh" check "$THREAD" 2>&1)" \
  || die "codex-cc-triage did not approve thread '$THREAD': $MARKER"
set -f
set -- $MARKER
set +f
[ "$#" -eq 8 ] && [ "$1" = CODEX_CC_REQUIRED_REVIEW ] && [ "$2" = APPROVE ] \
  && [ "$3" = "thread=$THREAD" ] && [ "$4" = "head=$SHA" ] \
  && [ "$7" = "base_sha=$BASE" ] && [ "$8" = "spec_path=$SPEC" ] \
  && case "$5:$6" in tree=?*:fingerprint=?*) true ;; *) false ;; esac \
  || die "codex-cc-triage marker does not cover thread, candidate, and spec"

ME="$($GH api user --jq .login 2>/dev/null)" \
  || die "cannot identify the authenticated GitHub account"
VERDICT="$(printf '%s' "$PRJSON" | jq -r --arg sha "$SHA" --arg me "$ME" '
  [ .reviews[]? | select((.commit.oid // "") == $sha and (.author.login // "") == $me) ]
  | sort_by(.submittedAt) | last | .body // ""
  | (split("\n")[0] // "") | sub("[ \\t\\r]+$"; "")
  | if test("^codex-tuner-verdict: (APPROVE|REQUEST_CHANGES) " + $sha + "$") then . else "" end')"
case "$VERDICT" in
  "codex-tuner-verdict: APPROVE $SHA") ;;
  "") die "no codex-tuner verdict from $ME on $SHA" ;;
  *) die "the latest codex-tuner verdict on $SHA is not an approval: $VERDICT" ;;
esac

CHECKS_ERR="$(mktemp "${TMPDIR:-/tmp}/codex-tuner-checks.XXXXXX")" \
  || die "cannot create a temporary file"
if ! CHECKS="$($GH pr checks "$PR" --required --json name,bucket 2>"$CHECKS_ERR")"; then
  if grep -Eq 'no( required)? checks reported' "$CHECKS_ERR"; then
    rm -f "$CHECKS_ERR"
    die "$PR has no required checks configured — absent CI is not green"
  fi
  rm -f "$CHECKS_ERR"
  die "cannot read required CI checks for $SHA"
fi
rm -f "$CHECKS_ERR"
TOTAL="$(printf '%s' "$CHECKS" | jq -r 'length // 0')"
[ "${TOTAL:-0}" -gt 0 ] 2>/dev/null || die "no required CI checks ran on $SHA"
BAD="$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket != "pass")] | length')"
[ "${BAD:-1}" -eq 0 ] 2>/dev/null || die "$BAD of $TOTAL required checks are not passing"

CURRENT_PRJSON="$($GH pr view "$PR" --json baseRefOid,headRefOid 2>/dev/null)" \
  || die "cannot re-read pull request '$PR' after CI"
CURRENT_HEAD="$(printf '%s' "$CURRENT_PRJSON" | jq -r '.headRefOid // empty')"
CURRENT_BASE="$(printf '%s' "$CURRENT_PRJSON" | jq -r '.baseRefOid // empty')"
[ "$CURRENT_HEAD" = "$SHA" ] && [ "$CURRENT_BASE" = "$BASE" ] \
  || die "PR head or base changed while merge readiness was checked"

if [ -n "$CHECK_ONLY" ]; then
  printf 'would merge %s (--%s) at %s: required review, public verdict, required CI, base, and head are current\n' \
    "$PR" "$STRATEGY" "$SHA"
  exit 0
fi

exec "$GH" pr merge "$PR" --"$STRATEGY" --match-head-commit "$SHA"
