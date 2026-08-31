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
    printf '{"baseRefName":"%s","baseRefOid":"%s","headRefOid":"%s","reviews":[{"commit":{"oid":"%s"},"author":{"login":"tester"},"submittedAt":"2026-08-31T00:00:00Z","body":"codex-tuner-verdict: %s %s\\nreview"}]}\n' \
      "${TEST_PR_BASE_REF:-main}" "$base" "$head" "$head" "${TEST_VERDICT:-APPROVE}" "$head"
    ;;
  'api user') printf 'tester\n' ;;
  'pr checks')
    if [ "${TEST_NO_CHECKS:-}" = 1 ]; then
      printf 'no required checks reported on the branch\n' >&2
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

run_merge() {
  rm -f "$T/pr-view-count"
  (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="${TEST_REVIEW_BASE:-$BASE}" \
    TEST_PR_BASE="${TEST_PR_BASE:-$BASE}" TEST_PR_VIEW_COUNT="$T/pr-view-count" \
    TEST_PR_BASE_REF="${TEST_PR_BASE_REF:-main}" TEST_REVIEWER="$REVIEWER" \
    TEST_MOVE_AFTER_CHECK="${TEST_MOVE_AFTER_CHECK:-}" \
    TEST_MOVE_BASE_AFTER_CHECK="${TEST_MOVE_BASE_AFTER_CHECK:-}" \
    "$MERGE" --check-only "${TEST_PR:-1}" squash "$SHA" task-review \
    "${TEST_ARG_BASE:-$BASE}" docs/spec.md)
}

output="$(run_merge)"
printf '%s' "$output" | grep -q 'required review, public verdict, required CI, base, and head are current'

rm -f "$T/pr-view-count"
output="$(cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="$BASE" \
  TEST_PR_BASE="$BASE" TEST_PR_VIEW_COUNT="$T/pr-view-count" TEST_REVIEWER="$REVIEWER" \
  "$MERGE" 1 squash "$SHA" task-review "$BASE" docs/spec.md)"
[ "$output" = merged ] || { echo "FAIL checked merge did not use the atomic head pin" >&2; exit 1; }

if TEST_NO_CHECKS=1 run_merge 2>"$T/error"; then
  echo "FAIL absent required CI passed" >&2
  exit 1
fi
grep -q 'absent CI is not green' "$T/error"

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
