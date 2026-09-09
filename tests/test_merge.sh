#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MERGE="$ROOT/plugins/codex-tuner/scripts/merge.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"; BIN="$T/bin"; REVIEWER="$T/reviewer"
mkdir -p "$REPO/docs" "$BIN" "$REVIEWER/scripts"

(
  cd "$REPO"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  printf 'base\n' > base.txt
  git add base.txt
  git commit -qm base
  printf '# Spec\n\n## Delivery\ntarget: main\n' > docs/spec.md
  printf 'candidate\n' > feature.txt
  git add docs/spec.md feature.txt
  git commit -qm candidate
)
SHA="$(git -C "$REPO" rev-parse HEAD)"
BASE="$(git -C "$REPO" rev-parse HEAD^)"

cat > "$REVIEWER/scripts/review-state.sh" <<'SH'
#!/usr/bin/env bash
printf 'CODEX_CC_REQUIRED_REVIEW APPROVE thread=%s head=%s tree=tree fingerprint=%064d base_sha=%s spec_path=docs/spec.md\n' "$2" "$TEST_SHA" 0 "$TEST_BASE"
SH
chmod +x "$REVIEWER/scripts/review-state.sh"

cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '{"installed":[{"pluginId":"codex-cc-triage@codex-cc-triage","installed":true,"enabled":true,"source":{"path":"%s"}}]}\n' "$TEST_REVIEWER"
SH
chmod +x "$BIN/codex"

cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
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
    comments='[]'
    if [ "${TEST_LOCAL_CI:-}" = 1 ]; then
      comments="$(printf '[{"author":{"login":"tester"},"body":"codex-tuner-local-ci: %s make test → ok\\nmore"}]' "$head")"
    elif [ "${TEST_LOCAL_CI:-}" = stale ]; then
      comments='[{"author":{"login":"tester"},"body":"codex-tuner-local-ci: 0000000000000000000000000000000000000000 make test → ok"}]'
    fi
    printf '{"baseRefName":"%s","baseRefOid":"%s","headRefOid":"%s","reviews":[{"commit":{"oid":"%s"},"author":{"login":"tester"},"submittedAt":"2026-08-31T00:00:00Z","body":"codex-tuner-verdict: %s %s\\nreview"}],"comments":%s}\n' \
      "${TEST_PR_BASE_REF:-main}" "$base" "$head" "$head" "${TEST_VERDICT:-APPROVE}" "$head" "$comments"
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
    printf '[{"name":"test","bucket":"%s"}]\n' "${TEST_CHECK_BUCKET:-pass}"
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
run_merge() {
  rm -f "$T/pr-view-count"
  (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="${TEST_REVIEW_BASE:-$BASE}" \
    TEST_PR_BASE="${TEST_PR_BASE:-$BASE}" TEST_PR_VIEW_COUNT="$T/pr-view-count" \
    TEST_PR_BASE_REF="${TEST_PR_BASE_REF:-main}" TEST_REVIEWER="$REVIEWER" \
    TEST_MOVE_AFTER_CHECK="${TEST_MOVE_AFTER_CHECK:-}" \
    TEST_MOVE_BASE_AFTER_CHECK="${TEST_MOVE_BASE_AFTER_CHECK:-}" \
    TEST_CHECKS_ARGV="$T/checks-argv" \
    "$MERGE" "$@" --check-only "${TEST_PR:-1}" squash "$SHA" task-review \
    "${TEST_ARG_BASE:-$BASE}" docs/spec.md)
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

if TEST_PR_BASE=0000000000000000000000000000000000000000 run_merge 2>"$T/error"; then
  echo "FAIL moved target base passed" >&2
  exit 1
fi
grep -q 'not the reviewed base' "$T/error"

if TEST_PR_BASE_REF=develop run_merge 2>"$T/error"; then
  echo "FAIL PR base branch outside the spec passed" >&2
  exit 1
fi
grep -q 'not spec target main' "$T/error"

if TEST_ARG_BASE="$SHA" TEST_REVIEW_BASE="$SHA" run_merge 2>"$T/error"; then
  echo "FAIL candidate accepted as its own review base" >&2
  exit 1
fi
grep -q 'not the reviewed base' "$T/error"

if TEST_PR='--repo=other/repository' run_merge 2>"$T/error"; then
  echo "FAIL option-like PR identifier passed" >&2
  exit 1
fi
grep -q 'pull request must be a positive number' "$T/error"

for bucket in fail pending skipping cancel; do
  if TEST_CHECK_BUCKET="$bucket" run_merge 2>"$T/error"; then
    echo "FAIL $bucket required CI passed" >&2
    exit 1
  fi
  grep -q 'required checks are not passing' "$T/error"
done

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

echo "PASS merge"
