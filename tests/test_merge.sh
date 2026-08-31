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
  printf '# Spec\n' > docs/spec.md
  printf 'candidate\n' > feature.txt
  git add docs/spec.md feature.txt
  git commit -qm candidate
)
SHA="$(git -C "$REPO" rev-parse HEAD)"

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
    printf '{"headRefOid":"%s","reviews":[{"commit":{"oid":"%s"},"author":{"login":"tester"},"submittedAt":"2026-08-31T00:00:00Z","body":"codex-tuner-verdict: %s %s\\nreview"}]}\n' \
      "${TEST_HEAD:-$TEST_SHA}" "${TEST_HEAD:-$TEST_SHA}" "${TEST_VERDICT:-APPROVE}" "${TEST_HEAD:-$TEST_SHA}"
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
  (cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="${TEST_BASE:-$SHA}" TEST_REVIEWER="$REVIEWER" \
    "$MERGE" --check-only 1 squash "$SHA" task-review "$SHA" docs/spec.md)
}

output="$(run_merge)"
printf '%s' "$output" | grep -q 'required review, public verdict, required CI, and head are current'

output="$(cd "$REPO" && PATH="$BIN:$PATH" TEST_SHA="$SHA" TEST_BASE="$SHA" \
  TEST_REVIEWER="$REVIEWER" "$MERGE" 1 squash "$SHA" task-review "$SHA" docs/spec.md)"
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

if TEST_BASE=0000000000000000000000000000000000000000 run_merge 2>"$T/error"; then
  echo "FAIL mismatched review base passed" >&2
  exit 1
fi
grep -q 'does not cover thread, candidate, and spec' "$T/error"

echo "PASS merge"
