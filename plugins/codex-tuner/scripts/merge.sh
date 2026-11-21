#!/usr/bin/env bash
# Checked merge boundary for codex-tuner.
#
# merge.sh [--check-only] [--ci required|any|none:<reason>] <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>
set -u

GH="${CODEX_TUNER_GH:-gh}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

die() { printf 'codex-tuner merge: %s\n' "$1" >&2; exit 1; }

# Older specs default to required CI. New contracts bind the mode below.
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
command -v jq >/dev/null 2>&1 || die "jq is required"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a Git repository"
cd "$ROOT" || exit 1
clean() {
  local changes
  changes="$(git status --porcelain -uall --ignore-submodules=none)" && [ -z "$changes" ]
}
clean || die "candidate worktree is not clean"
[ "$(git rev-parse HEAD)" = "$SHA" ] || die "current HEAD is not candidate $SHA"
[[ "$BASE" =~ ^[a-f0-9]+$ ]] && [ "${#BASE}" = "${#SHA}" ] || die "expected full base SHA"
CONTRACT="$(python3 "$SCRIPTS/delivery_spec.py" "$SHA" "$SPEC")" || exit 1
spec_field() { jq -r --arg key "$1" '.[$key] // ""' <<< "$CONTRACT"; }
SPEC_TARGET="$(spec_field target)"
HOST="$(spec_field host)"
[ "${HOST:-github}" = github ] || die "use the spec's $HOST delivery route"
DELIVERY="$(spec_field delivery)"
case "$DELIVERY" in ''|merge) ;; *) [ -n "$CHECK_ONLY" ] || die "spec delivery is $DELIVERY; merge is reserved" ;; esac
REVIEW="$(spec_field review)"
SPEC_CI="$(spec_field ci)"
REQUESTED_CI="$CI_MODE${CI_REASON:+:$CI_REASON}"
[ -z "$SPEC_CI" ] || [ "$REQUESTED_CI" = "$SPEC_CI" ] || die "CI mode differs from the spec"
SPEC_MERGE="$(spec_field merge)"
[ -z "$SPEC_MERGE" ] || [ "$SPEC_MERGE" = "$STRATEGY" ] || die "strategy differs from the spec"

DEST="$(python3 "$SCRIPTS/destination.py")" || die "cannot resolve delivery remote"
IFS=$'\t' read -r REMOTE FORGE PROJECT <<< "$DEST"
REPO="$FORGE/$PROJECT"
pr() { "$GH" pr "$@" --repo "$REPO"; }
api() { "$GH" api "$@" --hostname "$FORGE"; }
PRJSON="$(pr view "$PR" --json state,isDraft,isCrossRepository,baseRefName,baseRefOid,headRefName,headRefOid 2>/dev/null)" \
  || die "cannot resolve pull request '$PR'"
jq -e '.state == "OPEN" and .isCrossRepository == false' <<< "$PRJSON" >/dev/null \
  || die "expected an open PR in the delivery project"
jq -e '.isDraft == false' <<< "$PRJSON" >/dev/null || die "the PR is still a draft"
SPEC_BRANCH="$(spec_field branch)" || die "invalid spec branch"
[ -n "$SPEC_BRANCH" ] && [ "$SPEC_BRANCH" = "$(jq -r '.headRefName // empty' <<< "$PRJSON")" ] || die "PR source differs from the spec branch"
HEAD_SHA="$(printf '%s' "$PRJSON" | jq -r '.headRefOid // empty')"
BASE_REF="$(printf '%s' "$PRJSON" | jq -r '.baseRefName // empty')"
BASE_OID="$(printf '%s' "$PRJSON" | jq -r '.baseRefOid // empty')"
[ "$HEAD_SHA" = "$SHA" ] \
  || die "the head of $PR is ${HEAD_SHA:-unknown}, not candidate $SHA"
[ -n "$BASE_REF" ] && [ "$BASE_REF" = "$SPEC_TARGET" ] \
  || die "the base of $PR is ${BASE_REF:-unknown}, not spec target $SPEC_TARGET"
[ -n "$BASE_OID" ] || die "cannot read the current base of $PR"
# The review base stays fixed while the delivery target advances. Both must be in this history.
[ "$BASE" != "$SHA" ] || die "reviewed base $BASE must be a proper ancestor of the candidate, not the candidate itself"
git -C "$ROOT" merge-base --is-ancestor "$BASE" "$SHA" 2>/dev/null \
  || die "reviewed base $BASE is not an ancestor of candidate $SHA"
git -C "$ROOT" cat-file -e "$BASE_OID^{commit}" 2>/dev/null \
  || git -C "$ROOT" fetch -q "$REMOTE" "$BASE_REF" 2>/dev/null \
  || die "cannot resolve the current target tip $BASE_OID locally; fetch $BASE_REF and retry"
git -C "$ROOT" merge-base --is-ancestor "$BASE_OID" "$SHA" 2>/dev/null \
  || die "the target advanced to $BASE_OID and candidate $SHA does not include it — integrate the target, re-verify affected evidence, obtain approval for the new candidate, then merge"


case "$CI_MODE" in
  required) CI_SELECT="--required"; CI_LABEL="required" ;;
  *)        CI_SELECT="";           CI_LABEL="reported" ;;
esac
CHECKS_ERR="$(mktemp "${TMPDIR:-/tmp}/codex-tuner-checks.XXXXXX")" \
  || die "cannot create a temporary file"
NONE_REPORTED=""
# Unquoted on purpose: an empty CI_SELECT must expand to no argument at all, not to an empty one.
# shellcheck disable=SC2086
if ! CHECKS="$(pr checks "$PR" $CI_SELECT --json name,bucket 2>"$CHECKS_ERR")"; then
  if grep -Eq 'no( required)? checks reported' "$CHECKS_ERR"; then
    NONE_REPORTED=1
    CHECKS='[]'
  elif jq -e 'type == "array" and length > 0 and all(.[]; has("bucket"))' <<< "$CHECKS" >/dev/null 2>&1; then
    : # gh also returns nonzero for pending/failed checks with complete JSON results.
  else
    rm -f "$CHECKS_ERR"
    die "cannot read $CI_LABEL CI checks for $SHA"
  fi
fi
rm -f "$CHECKS_ERR"
TOTAL="$(jq -er 'if type == "array" then length else error("expected checks") end' <<< "$CHECKS")" || die "invalid CI checks response"

ME="$(api user --jq .login 2>/dev/null)" \
  || die "cannot identify the authenticated GitHub account"
[ -n "$ME" ] && [ "$ME" != null ] || die "missing GitHub account identity"
if [ -n "$DELIVERY" ] || [ "$CI_MODE" = none ]; then
  COMMENTS="$(api "repos/$PROJECT/issues/$PR/comments" --paginate --slurp)" || die "cannot read PR evidence"
fi
if [ -n "$DELIVERY" ]; then
  jq -e --arg sha "$SHA" --arg me "$ME" '
    any(.[][]; .user.login == $me and (.body | startswith("codex-tuner-verified: " + $sha + "\n"))
        and (.body | split("\n")[1:] | any(test("[^[:space:]]"))))' <<< "$COMMENTS" >/dev/null \
    || die "missing verification evidence for $SHA"
fi
REVIEWS="$(api "repos/$PROJECT/pulls/$PR/reviews" --paginate --slurp)" || die "cannot read PR review records"
VERDICT="$(jq -r --arg sha "$SHA" --arg me "$ME" '
  [.[][] | select(.commit_id == $sha and .user.login == $me and .state == "COMMENTED")
    | . + {first: ((.body // "") | split("\n")[0] | sub("[ \\t\\r]+$"; ""))}
    | select(.first == ("codex-tuner-verdict: APPROVE " + $sha)
          or .first == ("codex-tuner-verdict: REQUEST_CHANGES " + $sha))]
  | sort_by(.submitted_at, .id) | last | .first // ""' <<< "$REVIEWS")"
case "$VERDICT" in
  "codex-tuner-verdict: APPROVE $SHA") ;;
  "") die "no codex-tuner verdict from $ME on $SHA" ;;
  *) die "the latest codex-tuner verdict on $SHA is not an approval: $VERDICT" ;;
esac

if [ "$CI_MODE" = none ]; then
  { [ -n "$NONE_REPORTED" ] || [ "${TOTAL:-0}" -eq 0 ]; } 2>/dev/null \
    || die "the spec declares 'ci: none' but $TOTAL check(s) are reported on $SHA — a waiver covers CI that does not exist, never CI that ran. Correct the spec's ci: mode and let those checks decide."
  # Only the delivery account can attest to the local substitute.
  LOCAL_CI="$(printf '%s' "$COMMENTS" | jq -r --arg sha "$SHA" --arg me "$ME" '
    [ .[][] | select(.user.login == $me)
      | . + {first: ((.body // "") | (split("\n")[0] // "") | sub("[ \t\r]+$"; ""))}
      | select(.first | test("^codex-tuner-local-ci: " + $sha + " \\S.*$"))
      | "\(.first)   — " + (.user.login // "unknown") ]
    | last // ""')"
  [ -n "$LOCAL_CI" ] \
    || die "'ci: none' waives CI on $SHA, so what stood in for it has to be on the record. Write a file whose
  first line is 'codex-tuner-local-ci: $SHA <the command that ran, and what it returned>', then run:
  $GH pr comment $PR --repo $REPO --body-file <that file>"
  printf 'codex-tuner merge: no CI reported on %s; merging under a recorded waiver: %s\n' "$SHA" "$CI_REASON" >&2
  printf 'codex-tuner merge: local verification claimed on the pull request: %s\n' "$LOCAL_CI" >&2
else
  [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null || die "no $CI_LABEL CI checks ran on $SHA — absent CI is unproven CI. Make CI run on this commit, or correct the spec's 'ci:' mode to how this repository actually verifies a candidate, and re-run with the mode the spec then declares."
  # A skipped check (a job whose `if:` was false) counts neither way, as on GitHub; at least one
  # selected check must have passed.
  BAD="$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket != "pass" and .bucket != "skipping")] | length')"
  [ "${BAD:-1}" -eq 0 ] 2>/dev/null || die "$BAD of $TOTAL $CI_LABEL checks are not passing"
  PASSED="$(printf '%s' "$CHECKS" | jq -r '[.[] | select(.bucket == "pass")] | length')"
  [ "${PASSED:-0}" -gt 0 ] 2>/dev/null || die "all $TOTAL $CI_LABEL CI checks on $SHA were skipped, so no CI ran on it. Run an applicable validation workflow on this candidate, or hand it off with CI unproved and merge pending."
fi

CURRENT_PRJSON="$(pr view "$PR" --json state,isDraft,isCrossRepository,baseRefOid,headRefOid,baseRefName,headRefName 2>/dev/null)" \
  || die "cannot re-read pull request '$PR' after CI"
jq -e --arg head "$SHA" --arg base "$BASE_OID" --arg target "$SPEC_TARGET" --arg branch "$SPEC_BRANCH" '
  .headRefOid == $head and .baseRefOid == $base and .baseRefName == $target
  and .headRefName == $branch
  and .state == "OPEN" and .isCrossRepository == false and .isDraft == false' <<< "$CURRENT_PRJSON" >/dev/null \
  || die "PR head or base changed while merge readiness was checked, or the PR is no longer ready"
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SHA" ] && clean \
  || die "local candidate changed during checks"
if [ "${REVIEW:-claude}" = claude ]; then
  bash "$SCRIPTS/check-review.sh" "$THREAD" "$SHA" "$BASE" "$SPEC" >/dev/null || exit 1
fi

if [ -n "$CHECK_ONLY" ]; then
  printf 'would merge %s (--%s) at %s: required review, public verdict, CI (--ci %s), base, and head are current\n' \
    "$PR" "$STRATEGY" "$SHA" "$CI_MODE"
  exit 0
fi

exec "$GH" pr merge "$PR" --"$STRATEGY" --match-head-commit "$SHA" --repo "$REPO"
