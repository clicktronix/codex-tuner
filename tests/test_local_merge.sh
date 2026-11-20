#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/plugins/codex-tuner/scripts/local-merge.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
formats=(sha1)
if git init -q --object-format=sha256 "$TMP/probe" 2>/dev/null; then formats+=(sha256); fi
for format in "${formats[@]}"; do (
git init -q --object-format="$format" -b main "$TMP/repo-$format"
cd "$TMP/repo-$format"
git config user.name test
git config user.email test@example.invalid
git commit --allow-empty -qm base
base="$(git rev-parse HEAD)"
git worktree add -q -b task "$TMP/worktree-$format"
cd "$TMP/worktree-$format"
spec='Документы задачи.md'
cat > "$spec" <<'EOF'
## Delivery
branch: task
target: main
host: local
merge: ff
delivery: merge
review: local
ci: none:local fixture
EOF
git add -- "$spec"
git commit -qm candidate
sha="$(git rev-parse HEAD)"
gate() { python3 "$GATE" "$@" "$sha" local "$base" "$spec"; }
note() { git notes --ref=codex-tuner append -m "$1" "$sha"; }
if gate --check-only 2>/dev/null; then exit 1; fi
note "codex-tuner-verified: $sha
[test] local fixture passed"
note "codex-tuner-verdict: APPROVE $sha"
if gate --check-only 2>/dev/null; then echo "FAIL lost local CI"; exit 1; fi
note "codex-tuner-local-ci: $sha Bash fixture exited 0"
note "codex-tuner-verdict: REQUEST_CHANGES $sha"
if gate --check-only 2>/dev/null; then echo "FAIL stale judgement"; exit 1; fi
note "codex-tuner-verdict: APPROVE $sha"
gate --check-only
[ "$(git rev-parse main)" = "$base" ]
touch "$TMP/repo-$format/personal-edit"
if gate 2>/dev/null; then echo "FAIL dirty target advanced"; exit 1; fi
[ -f "$TMP/repo-$format/personal-edit" ] && [ "$(git rev-parse main)" = "$base" ]
rm "$TMP/repo-$format/personal-edit"
gate
[ "$(git -C "$TMP/repo-$format" rev-parse HEAD)" = "$sha" ]
test -f "$TMP/repo-$format/$spec"
# The same exact candidate with a target checked out nowhere uses compare-and-swap.
git -C "$TMP/repo-$format" checkout -q --detach main
git update-ref refs/heads/main "$base" "$sha"
gate
[ "$(git rev-parse refs/heads/main)" = "$sha" ]
# The local verdict receiver accepts the same object format as the candidate repository.
printf 'CODEX_CC_REQUIRED_REVIEW APPROVE thread=task head=%s tree=%s fingerprint=%064d base_sha=%s spec_path=%s\n' \
  "$sha" "$(git rev-parse HEAD^{tree})" 0 "$base" "$spec" > "$TMP/receipt"
python3 "$ROOT/plugins/codex-tuner/scripts/finish-review.py" "$TMP/receipt" | grep -Fq "codex-tuner-verdict: APPROVE $sha"
) ; done
echo "PASS local verification, refusal, preflight and pinned fast-forward"
