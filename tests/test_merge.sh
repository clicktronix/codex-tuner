#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MERGE="$ROOT/plugins/codex-tuner/scripts/merge.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"; BIN="$T/bin"; REVIEWER="$T/reviewer"
mkdir -p "$REPO/docs" "$BIN" "$REVIEWER/scripts" "$REVIEWER/.codex-plugin"
printf '{"name":"codex-cc-triage","version":"0.7.1"}\n' > "$REVIEWER/.codex-plugin/plugin.json"
export CODEX_HOME="$T/codex-home"

(
  cd "$REPO"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  git remote add origin https://example.invalid/team/repo.git
  git config protocol.https.allow never
  printf 'base\n' > base.txt
  git add base.txt
  git commit -qm base
  printf '# Spec\n\n## Delivery\ntarget: main\nbranch: task\n' > docs/spec.md
  for field in host review delivery; do
    { cat docs/spec.md; printf '%s: one\n%s: two\n' "$field" "$field"; } > "docs/dupe-$field.md"
  done
  cp docs/spec.md 'docs/План работы.md'
  { cat docs/spec.md; printf 'merge: squash\nci: any — all reported checks on the candidate\n'; } > docs/legacy.md
  printf '# Spec\n\n## Delivery\ntarget: main\nbranch: task\nhost: github\ndelivery: draft\nreview: local\nmerge: squash\nci: required\n' > docs/draft.md
  printf 'candidate\n' > feature.txt
  git add docs feature.txt
  git commit -qm candidate
)
SHA="$(git -C "$REPO" rev-parse HEAD)"
BASE="$(git -C "$REPO" rev-parse HEAD^)"
# An advanced target: a commit on top of the reviewed base that the candidate does NOT contain.
(
  cd "$REPO"
  git checkout -q -b advanced "$BASE"
  printf 'advanced\n' > advanced.txt
  git add advanced.txt
  git commit -qm 'target advanced'
  git checkout -q main
)
ADVANCED="$(git -C "$REPO" rev-parse advanced)"

cat > "$REVIEWER/scripts/review-state.sh" <<'SH'
#!/usr/bin/env bash
printf 'CODEX_CC_REQUIRED_REVIEW APPROVE thread=%s head=%s tree=%s fingerprint=%064d base_sha=%s spec_path=%s\n' "$2" "$TEST_SHA" "${TEST_TREE:-$(git rev-parse HEAD^{tree})}" 0 "$TEST_BASE" "${TEST_MARKER_SPEC:-docs/spec.md}"
SH
chmod +x "$REVIEWER/scripts/review-state.sh"

cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
if [ "${TEST_VERSION:-}" = legacy ]; then
  printf '{"installed":[{"pluginId":"codex-cc-triage@codex-cc-triage","installed":true,"enabled":true,"source":{"path":"%s"}}]}\n' "$TEST_REVIEWER"
  exit 0
fi
printf '{"installed":[{"pluginId":"codex-cc-triage@codex-cc-triage","installed":true,"enabled":true,"version":"%s","source":{"path":"%s"}}]}\n' "${TEST_VERSION:-0.7.1}" "$TEST_REVIEWER"
SH
chmod +x "$BIN/codex"

cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  pr) [[ " $* " = *' --repo example.invalid/team/repo '* ]] || exit 7 ;;
  api) [[ " $* " = *' --hostname example.invalid '* ]] || exit 7 ;;
esac
case "$1 $2" in
  'pr view')
    count=0
    [ ! -f "$TEST_PR_VIEW_COUNT" ] || count="$(cat "$TEST_PR_VIEW_COUNT")"
    count=$((count + 1)); printf '%s\n' "$count" > "$TEST_PR_VIEW_COUNT"
    head="${TEST_HEAD:-$TEST_SHA}"
    if [ "${TEST_MOVE_AFTER_CHECK:-}" = 1 ] && [ "$count" -gt 1 ]; then
      head=0000000000000000000000000000000000000000
    fi
    base="$TEST_PR_BASE"
    if [ "${TEST_MOVE_BASE_AFTER_CHECK:-}" = 1 ] && [ "$count" -gt 1 ]; then
      base=0000000000000000000000000000000000000000
    fi
    target="${TEST_PR_BASE_REF:-main}"
    if [ "${TEST_RETARGET_AFTER_CHECK:-}" = 1 ] && [ "$count" -gt 1 ]; then target=other; fi
    printf '{"state":"OPEN","isDraft":%s,"isCrossRepository":false,"baseRefName":"%s","baseRefOid":"%s","headRefName":"task","headRefOid":"%s"}\n' "${TEST_DRAFT:-false}" "$target" "$base" "$head"
    ;;
  'api repos/team/repo/issues/1/comments')
    sha="$TEST_SHA"
    case "${TEST_LOCAL_CI:-}" in
      1|other) ;;
      stale) sha=0000000000000000000000000000000000000000 ;;
      *) sha="" ;;
    esac
    user=tester
    [ "${TEST_LOCAL_CI:-}" != other ] || user=stranger
    jq -nc --arg sha "$sha" --arg user "$user" --arg verified "${TEST_VERIFIED:-}" '
      [[(if $sha != "" then {user:{login:$user},body:("codex-tuner-local-ci: " + $sha + " make test → ok")} else empty end),
        (if $verified != "" then {user:{login:"tester"},body:("codex-tuner-verified: " + $verified + "\ntest passed")} else empty end)]]'
    ;;
  'api repos/team/repo/pulls/1/reviews')
    printf '[[{"id":12,"user":{"login":"tester"},"commit_id":"%s","state":"COMMENTED","submitted_at":"2026-08-31T00:00:00Z","body":"codex-tuner-verdict: %s %s\\nreview"}]]\n' "$TEST_SHA" "${TEST_VERDICT:-APPROVE}" "$TEST_SHA"
    ;;
  'api user') printf 'tester\n' ;;
  'pr checks')
    # Record whether --required was passed so a test can prove the mode selected the right query.
    [ -z "${TEST_CHECKS_ARGV:-}" ] || printf '%s\n' "$*" > "$TEST_CHECKS_ARGV"
    if [ "${TEST_NO_CHECKS:-}" = 1 ]; then
      case "$*" in *--required*) printf 'no required checks reported on the branch\n' >&2 ;;
                   *)            printf 'no checks reported on the branch\n' >&2 ;; esac
      exit 1
    fi
    if [ -n "${TEST_CHECKS_JSON:-}" ]; then
      printf '%s\n' "$TEST_CHECKS_JSON"
    else
      printf '[{"name":"test","bucket":"%s"}]\n' "${TEST_CHECK_BUCKET:-pass}"
    fi
    exit "${TEST_CHECK_RC:-0}"
    ;;
  'pr merge')
    [ "$3" = 1 ] && [ "$4" = --squash ] && [ "$5" = --match-head-commit ] \
      && [ "$6" = "$TEST_SHA" ] || exit 3
    printf 'merged\n'
    ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 2 ;;
esac
SH
chmod +x "$BIN/gh"

# Leading arguments are flags placed before --check-only, so a test can pass --ci <mode>.
# TEST_CAND overrides the candidate SHA (default: the fixture's original candidate).
run_merge() {
  rm -f "$T/pr-view-count"
  local cand="${TEST_CAND:-$SHA}"
  (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$cand" TEST_BASE="${TEST_REVIEW_BASE:-$BASE}" \
    TEST_PR_BASE="${TEST_PR_BASE:-$BASE}" TEST_PR_VIEW_COUNT="$T/pr-view-count" \
    TEST_PR_BASE_REF="${TEST_PR_BASE_REF:-main}" TEST_REVIEWER="$REVIEWER" \
    TEST_MOVE_AFTER_CHECK="${TEST_MOVE_AFTER_CHECK:-}" \
    TEST_MOVE_BASE_AFTER_CHECK="${TEST_MOVE_BASE_AFTER_CHECK:-}" \
    TEST_CHECKS_ARGV="$T/checks-argv" \
    "$MERGE" "$@" --check-only "${TEST_PR:-1}" squash "$cand" task-review \
    "${TEST_ARG_BASE:-$BASE}" "${TEST_SPEC:-docs/spec.md}")
}

output="$(run_merge)"
printf '%s' "$output" | grep -q 'required review, public verdict, CI (--ci required), base, and head are current'
grep -q -- '--required' "$T/checks-argv" || { echo "FAIL default mode did not query required checks" >&2; exit 1; }

rm -f "$T/pr-view-count"
output="$(cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="$BASE" \
  TEST_PR_BASE="$BASE" TEST_PR_VIEW_COUNT="$T/pr-view-count" TEST_REVIEWER="$REVIEWER" \
  "$MERGE" 1 squash "$SHA" task-review "$BASE" docs/spec.md)"
[ "$output" = merged ] || { echo "FAIL checked merge did not use the atomic head pin" >&2; exit 1; }

if TEST_NO_CHECKS=1 run_merge 2>"$T/error"; then
  echo "FAIL absent required CI passed" >&2
  exit 1
fi
grep -q 'absent CI is unproven CI' "$T/error"

# --ci any: every reported check, at least one, queried WITHOUT --required.
output="$(run_merge --ci any)"
printf '%s' "$output" | grep -q 'CI (--ci any)'
if grep -q -- '--required' "$T/checks-argv"; then
  echo "FAIL --ci any still queried only required checks" >&2; exit 1
fi
if TEST_NO_CHECKS=1 run_merge --ci any 2>"$T/error"; then
  echo "FAIL --ci any passed with no reported checks" >&2
  exit 1
fi
grep -q 'no reported CI checks ran' "$T/error"
if TEST_CHECK_BUCKET=fail run_merge --ci any 2>"$T/error"; then
  echo "FAIL --ci any passed a failing reported check" >&2
  exit 1
fi
grep -q 'reported checks are not passing' "$T/error"

# --ci none:<reason>: only with zero reported checks AND an exact-SHA local-CI comment.
output="$(TEST_NO_CHECKS=1 TEST_LOCAL_CI=1 run_merge --ci 'none:manual runner, minutes are paid' 2>"$T/error")"
printf '%s' "$output" | grep -q 'CI (--ci none)'
grep -q 'merging under a recorded waiver: manual runner, minutes are paid' "$T/error"
grep -q 'local verification claimed on the pull request: codex-tuner-local-ci:' "$T/error"
if TEST_NO_CHECKS=1 run_merge --ci none:manual 2>"$T/error"; then
  echo "FAIL --ci none passed without a local-CI record" >&2
  exit 1
fi
grep -q 'has to be on the record' "$T/error"
# The hint is copied with a check's output pasted in: inside --body "..." the shell would expand
# backticks and $(...) from that output, so the record goes through a file.
grep -q -- '--body-file' "$T/error" || { echo "FAIL local-CI hint does not use --body-file" >&2; exit 1; }
if grep -q -- '--body ' "$T/error"; then echo "FAIL local-CI hint passes the record inline" >&2; exit 1; fi
if TEST_NO_CHECKS=1 TEST_LOCAL_CI=stale run_merge --ci none:manual 2>"$T/error"; then
  echo "FAIL --ci none accepted a local-CI record for another SHA" >&2
  exit 1
fi
grep -q 'has to be on the record' "$T/error"
if TEST_LOCAL_CI=1 run_merge --ci none:manual 2>"$T/error"; then
  echo "FAIL --ci none waived a check that actually ran" >&2
  exit 1
fi
grep -q 'a waiver covers CI that does not exist, never CI that ran' "$T/error"
if TEST_CHECK_BUCKET=fail TEST_LOCAL_CI=1 run_merge --ci none:manual 2>"$T/error"; then
  echo "FAIL --ci none waived a failing check" >&2
  exit 1
fi
grep -q 'never CI that ran' "$T/error"

# Mode grammar and flag placement.
if run_merge --ci none 2>"$T/error"; then
  echo "FAIL --ci none without a reason passed" >&2; exit 1
fi
grep -q 'needs a reason' "$T/error"
if run_merge --ci bogus 2>"$T/error"; then
  echo "FAIL unknown --ci mode passed" >&2; exit 1
fi
grep -q "unknown --ci mode 'bogus'" "$T/error"
if (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="$BASE" TEST_PR_BASE="$BASE" \
      TEST_PR_VIEW_COUNT="$T/pr-view-count" TEST_REVIEWER="$REVIEWER" \
      "$MERGE" --check-only 1 squash "$SHA" task-review "$BASE" docs/spec.md --ci any) 2>"$T/error"; then
  echo "FAIL a flag after the positionals was accepted" >&2; exit 1
fi
grep -q 'too many arguments' "$T/error"
if (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="$BASE" TEST_PR_BASE="$BASE" \
      TEST_PR_VIEW_COUNT="$T/pr-view-count" TEST_REVIEWER="$REVIEWER" \
      "$MERGE" --check-only 1 squash "$SHA" --ci "$BASE" docs/spec.md) 2>"$T/error"; then
  echo "FAIL a flag in the thread position was accepted" >&2; exit 1
fi
grep -q 'looks like a flag' "$T/error"

if TEST_VERDICT=REQUEST_CHANGES run_merge 2>"$T/error"; then
  echo "FAIL REQUEST_CHANGES passed" >&2
  exit 1
fi
grep -q 'not an approval' "$T/error"

if TEST_HEAD=0000000000000000000000000000000000000000 run_merge 2>"$T/error"; then
  echo "FAIL moved PR head passed" >&2
  exit 1
fi
grep -q 'not candidate' "$T/error"

if TEST_REVIEW_BASE=0000000000000000000000000000000000000000 run_merge 2>"$T/error"; then
  echo "FAIL mismatched review base passed" >&2
  exit 1
fi
grep -q 'does not cover thread, candidate, and spec' "$T/error"

# The target advanced after the review was opened — an ordinary long task. Two halves, both real:
# equality of the PR's current base with the reviewed base was a dead end (a re-approved, integrated
# candidate could never merge), but a candidate that does NOT yet contain the advanced target must
# still be refused: the head pin protects the head, and GitHub would merge a tree nobody reviewed.
if TEST_PR_BASE="$ADVANCED" run_merge 2>"$T/error"; then
  echo "FAIL a candidate that does not include the advanced target was accepted" >&2
  exit 1
fi
grep -q 'does not include it' "$T/error"
# A base GitHub reports that cannot be resolved locally is a fetch problem, named as such.
if TEST_PR_BASE=0000000000000000000000000000000000000000 run_merge 2>"$T/error"; then
  echo "FAIL an unresolvable target tip passed" >&2
  exit 1
fi
grep -q 'cannot resolve the current target tip' "$T/error"

if TEST_PR_BASE_REF=develop run_merge 2>"$T/error"; then
  echo "FAIL PR base branch outside the spec passed" >&2
  exit 1
fi
grep -q 'not spec target main' "$T/error"

if TEST_ARG_BASE="$SHA" TEST_REVIEW_BASE="$SHA" run_merge 2>"$T/error"; then
  echo "FAIL candidate accepted as its own review base" >&2
  exit 1
fi
grep -q 'must be a proper ancestor of the candidate' "$T/error"

if TEST_PR='--repo=other/repository' run_merge 2>"$T/error"; then
  echo "FAIL option-like PR identifier passed" >&2
  exit 1
fi
grep -q 'pull request must be a positive number' "$T/error"

for bucket in fail pending cancel; do
  if TEST_CHECK_BUCKET="$bucket" run_merge 2>"$T/error"; then
    echo "FAIL $bucket required CI passed" >&2
    exit 1
  fi
  grep -q 'required checks are not passing' "$T/error"
done

# A skipped check (a job whose `if:` was false) counts neither way, as on GitHub; at least one
# selected check must pass, and pending, failed or cancelled ones still block.
for mode in required any; do
  output="$(TEST_CHECKS_JSON='[{"name":"test","bucket":"pass"},{"name":"deploy-docs","bucket":"skipping"}]' run_merge --ci "$mode")" \
    || { echo "FAIL a pass plus a skipped $mode check did not merge" >&2; exit 1; }
  printf '%s' "$output" | grep -q "CI (--ci $mode)"
  if TEST_CHECKS_JSON='[{"name":"test","bucket":"skipping"},{"name":"e2e","bucket":"skipping"}]' run_merge --ci "$mode" 2>"$T/error"; then
    echo "FAIL all skipped $mode checks passed" >&2; exit 1
  fi
  grep -q 'were skipped, so no CI ran' "$T/error"
  if TEST_CHECKS_JSON='[{"name":"test","bucket":"pass"},{"name":"e2e","bucket":"pending"}]' TEST_CHECK_RC=8 run_merge --ci "$mode" 2>"$T/error"; then
    echo "FAIL a pass plus a pending $mode check passed" >&2; exit 1
  fi
  grep -q '1 of 2 .* checks are not passing' "$T/error"
done

if TEST_CHECK_BUCKET=pending TEST_CHECK_RC=8 run_merge 2>"$T/error"; then
  echo "FAIL gh pending response passed"; exit 1
fi
grep -q 'required checks are not passing' "$T/error"

if TEST_MOVE_AFTER_CHECK=1 run_merge 2>"$T/error"; then
  echo "FAIL moved PR head passed check-only revalidation" >&2
  exit 1
fi
grep -q 'changed while merge readiness was checked' "$T/error"

if TEST_MOVE_BASE_AFTER_CHECK=1 run_merge 2>"$T/error"; then
  echo "FAIL moved PR base passed check-only revalidation" >&2
  exit 1
fi
grep -q 'changed while merge readiness was checked' "$T/error"

TEST_VERSION=legacy TEST_SPEC=docs/legacy.md TEST_MARKER_SPEC=docs/legacy.md run_merge --ci any >/dev/null
if TEST_VERSION=8.0.0 run_merge 2>"$T/error"; then echo 'FAIL registry version mismatch accepted'; exit 1; fi
grep -q 'does not match' "$T/error"
cache="$CODEX_HOME/plugins/cache/codex-cc-triage/codex-cc-triage/8.0.0"
mkdir -p "$cache"
cp -R "$REVIEWER/." "$cache"
printf '{"name":"codex-cc-triage","version":"8.0.0"}\n' > "$cache/.codex-plugin/plugin.json"
TEST_VERSION=8.0.0 run_merge >/dev/null
for field in host review delivery; do
  if TEST_SPEC="docs/dupe-$field.md" run_merge 2>"$T/error"; then echo "FAIL ambiguous $field"; exit 1; fi
  grep -q "duplicate or empty spec field $field" "$T/error"
done
output="$(TEST_SPEC='docs/План работы.md' TEST_MARKER_SPEC='docs/План работы.md' run_merge)"
[[ "$output" = *'would merge 1'* ]]
for envcase in wrong-tree wrong-spec; do
  if [ "$envcase" = wrong-tree ]; then export TEST_TREE="$BASE"; else export TEST_MARKER_SPEC='docs/wrong plan.md'; fi
  if run_merge 2>"$T/error"; then echo "FAIL $envcase passed" >&2; exit 1; fi
  grep -q 'does not cover' "$T/error"
  unset TEST_TREE TEST_MARKER_SPEC
done
if TEST_SPEC=docs/draft.md run_merge 2>"$T/error"; then echo 'FAIL unverified new-format spec passed' >&2; exit 1; fi
grep -q 'missing verification evidence' "$T/error"
TEST_SPEC=docs/draft.md TEST_VERIFIED="$SHA" run_merge >/dev/null
if TEST_SPEC=docs/draft.md run_merge --ci any 2>"$T/error"; then echo 'FAIL weaker CI mode passed' >&2; exit 1; fi
grep -q 'CI mode differs' "$T/error"
if (cd "$REPO" && "$MERGE" 1 squash "$SHA" local "$BASE" docs/draft.md) 2>"$T/error"; then echo 'FAIL draft authorized merge' >&2; exit 1; fi
grep -q 'merge is reserved' "$T/error"
if TEST_NO_CHECKS=1 TEST_LOCAL_CI=other run_merge --ci none:manual 2>"$T/error"; then echo 'FAIL another author supplied local CI' >&2; exit 1; fi
git -C "$REPO" remote set-url --add --push origin https://example.invalid/team/other.git
if run_merge 2>"$T/error"; then echo 'FAIL split fetch/push routes passed' >&2; exit 1; fi
grep -q 'fetch and push' "$T/error"
git -C "$REPO" config --unset-all remote.origin.pushurl

if TEST_RETARGET_AFTER_CHECK=1 run_merge 2>"$T/error"; then echo 'FAIL PR retargeted to a different branch at the same SHA'; exit 1; fi
grep -q 'changed while merge readiness was checked' "$T/error"
if TEST_DRAFT=true run_merge 2>"$T/error"; then echo 'FAIL draft reported ready to merge'; exit 1; fi
grep -q 'still a draft' "$T/error"

# The integrated half: after the workflow merges the advanced target into the candidate and the new
# SHA is approved, the reviewed base is still a proper ancestor and the target is now inside the
# candidate — this is the path the old equality check made impossible. Last, because it moves HEAD.
(
  cd "$REPO"
  git merge -q --no-edit advanced
)
INTEGRATED="$(git -C "$REPO" rev-parse HEAD)"
output="$(TEST_CAND="$INTEGRATED" TEST_PR_BASE="$ADVANCED" run_merge)"
printf '%s' "$output" | grep -q "would merge 1 (--squash) at $INTEGRATED" \
  || { echo "FAIL an integrated, re-approved candidate was blocked by the advanced target: $output" >&2; exit 1; }

echo "PASS merge"
