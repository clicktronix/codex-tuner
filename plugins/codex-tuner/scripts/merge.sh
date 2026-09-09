#!/usr/bin/env bash
# Checked merge boundary for codex-tuner.
#
# merge.sh [--check-only] [--ci required|any|none:<reason>] <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>
set -u

GH="${CODEX_TUNER_GH:-gh}"

die() { printf 'codex-tuner merge: %s\n' "$1" >&2; exit 1; }

# CI policy, defaulting to the strictest. It is an argument rather than a constant because "required"
# is not universal: a repository with no branch protection has no required checks at all, and one
# whose CI is triggered by hand has none on a given head. Refusing both outright did not make them
# safer — it sent the operator to `gh pr merge` by hand, outside every check in this file. The mode
# is the spec's declaration (`ci:`), passed verbatim by run; it is not chosen at the merge boundary.
CHECK_ONLY=""
CI_MODE=required
CI_REASON=""
while :; do
  case "${1:-}" in
    --check-only) CHECK_ONLY=1; shift ;;
    --ci)
      [ -n "${2:-}" ] || die "--ci needs a mode: required, any, or none:<reason>"
      case "$2" in
        required|any) CI_MODE="$2" ;;
        none:?*)      CI_MODE=none; CI_REASON="${2#none:}" ;;
        none|none:)   die "--ci none needs a reason: --ci 'none:<why this repository runs no CI>'" ;;
        *)            die "unknown --ci mode '$2' (expected required, any, or none:<reason>)" ;;
      esac
      shift 2 ;;
    *) break ;;
  esac
done

PR="${1:-}"; STRATEGY="${2:-}"; SHA="${3:-}"; THREAD="${4:-}"; BASE="${5:-}"; SPEC="${6:-}"
[ -n "$PR" ] && [ -n "$STRATEGY" ] && [ -n "$SHA" ] && [ -n "$THREAD" ] \
  && [ -n "$BASE" ] && [ -n "$SPEC" ] \
  || die "usage: merge.sh [--check-only] [--ci required|any|none:<reason>] <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>"
# Options are read before the positionals, so a flag written after them is not a flag. Taking it
# silently as a positional refuses for a reason that names the wrong problem.
[ "$#" -le 6 ] || die "too many arguments: '$7' came after the positional ones. Flags go first: merge.sh [--check-only] [--ci <mode>] <pr> <strategy> <sha> <thread> <base> <spec>"
case "$THREAD" in --*) die "'$THREAD' looks like a flag, but it is in the review-thread position — flags go before <pr>" ;; esac
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

PRJSON="$($GH pr view "$PR" --json baseRefName,baseRefOid,headRefOid,reviews,comments 2>/dev/null)" \
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

# CI, in the mode the spec declared:
#   required (default) — GitHub's own required checks; the repository declared what must pass.
#   any                — every check reported on the head, at least one. For a repository that runs
#                        CI without branch protection. A workflow that never started reports nothing,
#                        which is why one check is still demanded.
#   none:<reason>      — a recorded waiver, honoured ONLY when GitHub reports no checks whatsoever on
#                        the head, and only with a local-CI record on the PR naming this exact SHA.
#                        A waiver over a failing or pending check is refused: absence is what a human
#                        can take responsibility for, failure is not.
# `gh pr checks` does not return an empty list when there is nothing to report: it exits non-zero
# with "no checks reported" / "no required checks reported" on stderr.
case "$CI_MODE" in
  required) CI_SELECT="--required"; CI_LABEL="required" ;;
  *)        CI_SELECT="";           CI_LABEL="reported" ;;
esac
CHECKS_ERR="$(mktemp "${TMPDIR:-/tmp}/codex-tuner-checks.XXXXXX")" \
  || die "cannot create a temporary file"
NONE_REPORTED=""
# Unquoted on purpose: an empty CI_SELECT must expand to no argument at all, not to an empty one.
# shellcheck disable=SC2086
if ! CHECKS="$($GH pr checks "$PR" $CI_SELECT --json name,bucket 2>"$CHECKS_ERR")"; then
  if grep -Eq 'no( required)? checks reported' "$CHECKS_ERR"; then
    NONE_REPORTED=1
    CHECKS='[]'
  else
    rm -f "$CHECKS_ERR"
    die "cannot read $CI_LABEL CI checks for $SHA"
  fi
fi
rm -f "$CHECKS_ERR"
TOTAL="$(printf '%s' "$CHECKS" | jq -r 'length // 0')"

if [ "$CI_MODE" = none ]; then
  { [ -n "$NONE_REPORTED" ] || [ "${TOTAL:-0}" -eq 0 ]; } 2>/dev/null \
    || die "the spec declares 'ci: none' but $TOTAL check(s) are reported on $SHA — a waiver covers CI that does not exist, never CI that ran. Correct the spec's ci: mode and let those checks decide."
  # "No checks reported" is not evidence in a repository whose policy is to report none. So `none`
  # additionally demands that whatever stood in for CI be written on the pull request, naming this
  # exact commit. This is an attributable claim, not a check: nothing here re-runs what it describes.
  # A comment, not the body: `gh pr edit --body` replaces the description. Any author; printed.
  LOCAL_CI="$(printf '%s' "$PRJSON" | jq -r --arg sha "$SHA" '
    [ .comments[]?
      | . + {first: ((.body // "") | (split("\n")[0] // "") | sub("[ \t\r]+$"; ""))}
      | select(.first | test("^codex-tuner-local-ci: " + $sha + " \\S.*$"))
      | "\(.first)   — " + (.author.login // "unknown") ]
    | last // ""')"
  [ -n "$LOCAL_CI" ] \
    || die "'ci: none' waives CI on $SHA, so what stood in for it has to be on the record:
  $GH pr comment $PR --body \"codex-tuner-local-ci: $SHA <the command that ran, and what it returned>\""
  printf 'codex-tuner merge: no CI reported on %s; merging under a recorded waiver: %s\n' "$SHA" "$CI_REASON" >&2
  printf 'codex-tuner merge: local verification claimed on the pull request: %s\n' "$LOCAL_CI" >&2
else
  # Names the fix without offering a menu: the mode is the spec's declaration, and a message listing
  # the other modes invites exactly the substitution run forbids.
  [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null || die "no $CI_LABEL CI checks ran on $SHA — absent CI is unproven CI. Make CI run on this commit, or correct the spec's 'ci:' mode to how this repository actually verifies a candidate, and re-run with the mode the spec then declares."
  BAD="$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket != "pass")] | length')"
  [ "${BAD:-1}" -eq 0 ] 2>/dev/null || die "$BAD of $TOTAL $CI_LABEL checks are not passing"
fi

CURRENT_PRJSON="$($GH pr view "$PR" --json baseRefOid,headRefOid 2>/dev/null)" \
  || die "cannot re-read pull request '$PR' after CI"
CURRENT_HEAD="$(printf '%s' "$CURRENT_PRJSON" | jq -r '.headRefOid // empty')"
CURRENT_BASE="$(printf '%s' "$CURRENT_PRJSON" | jq -r '.baseRefOid // empty')"
[ "$CURRENT_HEAD" = "$SHA" ] && [ "$CURRENT_BASE" = "$BASE" ] \
  || die "PR head or base changed while merge readiness was checked"

if [ -n "$CHECK_ONLY" ]; then
  printf 'would merge %s (--%s) at %s: required review, public verdict, CI (--ci %s), base, and head are current\n' \
    "$PR" "$STRATEGY" "$SHA" "$CI_MODE"
  exit 0
fi

exec "$GH" pr merge "$PR" --"$STRATEGY" --match-head-commit "$SHA"
