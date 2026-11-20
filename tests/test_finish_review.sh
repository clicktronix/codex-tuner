#!/usr/bin/env bash
# Exercise the actual round publisher against a real checkout and a stateful GitHub stub.
set -eu
PLUGIN="$(cd "$(dirname "$0")/../plugins/codex-tuner" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export REMOTE_STATE="$work/state"
mkdir "$REMOTE_STATE" "$work/bin"
export PATH="$work/bin:$PATH"
unset CODEX_TUNER_GH CODEX_TUNER_REMOTE
git init -q "$work/repo"
cd "$work/repo"
git remote add origin https://github.com/example/fixture.git
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -eu
echo "$*" >> "$REMOTE_STATE/calls"
if [ "$1 $2" = 'auth status' ]; then exit 0; fi
[ "$1 $2 $3" = 'api --hostname github.com' ] || exit 2
shift 3
endpoint=repos/example/fixture/pulls/2
case "$*" in
  user) echo '{"id":17}' ;;
  "--paginate --slurp $endpoint/reviews") jq -s '[.]' "$REMOTE_STATE/reviews" ;;
  "--paginate --slurp repos/example/fixture/pulls/3/reviews") echo '[[]]' ;;
  "$endpoint"|repos/example/fixture/pulls/3)
    source=task; [ "$1" = "$endpoint" ] || source=another-task
    jq -n --arg sha "$(cat "$REMOTE_STATE/head")" --arg source "$source" \
      --arg state "${PULL_STATE:-open}" --arg target "${PULL_TARGET:-main}" \
      --arg origin "${PULL_ORIGIN:-example/fixture}" --arg dest "${PULL_DEST:-example/fixture}" \
      '{state:$state,head:{sha:$sha,ref:$source,repo:{full_name:$origin}},base:{ref:$target,repo:{full_name:$dest}}}' ;;
  "repos/example/fixture/pulls/3/reviews --method POST"*) echo unexpected >> "$REMOTE_STATE/wrong-pr"; exit 0 ;;
  "--paginate --slurp $endpoint/commits") jq -Rs '[split("\n")|map(select(length>0)|{sha:.})]' "$REMOTE_STATE/commits" ;;
  "$endpoint/reviews --method POST -f event=COMMENT -f commit_id="*)
    [ "$8" = '-f' ]
    jq -cn --arg sha "${7#commit_id=}" --arg body "${9#body=}" \
      '{commit_id:$sha,body:$body,state:"COMMENTED",user:{id:17},html_url:"review-url"}' >> "$REMOTE_STATE/reviews"
    [ ! -f "$REMOTE_STATE/drop-response" ] || exit 1
    echo review-url ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$work/bin/gh"
: > "$REMOTE_STATE/reviews"
spec='docs/План работы.md'
git config user.email test@example.invalid
git config user.name test
mkdir docs
printf '## Delivery\nbranch: task\ntarget: main\nhost: github\nreview: local\ndelivery: draft\n' > "$spec"
git add -- "$spec"
git commit -qm 'candidate A'
a="$(git rev-parse HEAD)"
git commit --allow-empty -qm 'candidate B'
b="$(git rev-parse HEAD)"
printf '%s\n' "$a" > "$REMOTE_STATE/head"
printf '%s\n' "$a" "$b" > "$REMOTE_STATE/commits"
publish() { python3 "$PLUGIN/scripts/finish-review.py" "$@" --spec "$spec"; }
printf 'CODEX_CC_REQUIRED_REVIEW APPROVE thread=task head=%s tree=%s fingerprint=%064d base_sha=%s spec_path=docs/План работы.md\n' "$a" "$a" 0 "$b" > "$work/round-1"

publish "$work/round-1"
[ ! -e "$REMOTE_STATE/calls" ]
# Both PRs point to the same commit and project but represent different tasks.
if publish "$work/round-1" --pr 3 2>"$work/error"; then echo 'FAIL verdict posted to another task'; exit 1; fi
grep -q 'source or target' "$work/error"
[ ! -e "$REMOTE_STATE/wrong-pr" ]
for change in 'PULL_STATE=closed' 'PULL_TARGET=other' 'PULL_ORIGIN=other/fork' 'PULL_DEST=other/repo'; do
  if env "$change" python3 "$PLUGIN/scripts/finish-review.py" "$work/round-1" --pr 2 --spec "$spec" 2>"$work/error"; then exit 1; fi
done
[ ! -s "$REMOTE_STATE/reviews" ]
touch "$REMOTE_STATE/drop-response"
if publish "$work/round-1" --pr 2; then exit 1; fi
rm "$REMOTE_STATE/drop-response"
PULL_STATE=closed publish "$work/round-1" --pr 2
publish "$work/round-1" --pr 2
[ "$(wc -l < "$REMOTE_STATE/reviews" | tr -d ' ')" = 1 ]
printf '%s\n' "$b" > "$REMOTE_STATE/head"  # the README fix is now pushed
printf 'codex-tuner-verdict: APPROVE %s\n' "$b" > "$work/round-2"
publish "$work/round-2" --pr 2
jq -es --arg a "$a" --arg b "$b" \
  'map(.commit_id) == [$a,$b] and all(.[]; (.body|split("\n")[0]) == ("codex-tuner-verdict: APPROVE " + .commit_id))' "$REMOTE_STATE/reviews"
# A later round on the same commit has its own decision. Replaying A must not supersede it.
printf 'codex-tuner-verdict: REQUEST_CHANGES %s\n' "$b" > "$work/round-3"
publish "$work/round-3" --pr 2
publish "$work/round-1" --pr 2
jq -es 'length == 3 and (last.body|startswith("codex-tuner-verdict: REQUEST_CHANGES "))' "$REMOTE_STATE/reviews"
# If publication was delayed until the head moved, post against the original commit.
cp "$work/round-1" "$work/delayed"
publish "$work/delayed" --pr 2
jq -es --arg a "$a" 'last.commit_id == $a' "$REMOTE_STATE/reviews"
printf 'codex-tuner-verdict: APPROVE %040d\n' 3 > "$work/unrelated"
if publish "$work/unrelated" --pr 2; then exit 1; fi
printf 'NO_DECISION\n' > "$work/incomplete"
if publish "$work/incomplete" --pr 2; then exit 1; fi
jq -es 'length == 4' "$REMOTE_STATE/reviews"
# An entry from a deleted or different account cannot acknowledge our round.
jq -c '.user = null' "$REMOTE_STATE/reviews" > "$work/foreign"
jq -c '.user = {"id":99}' "$REMOTE_STATE/reviews" >> "$work/foreign"
mv "$work/foreign" "$REMOTE_STATE/reviews"
publish "$work/round-1" --pr 2
jq -es '[.[]|select(.user.id==17)]|length==1' "$REMOTE_STATE/reviews"
# Reusing a receipt filename for a different judgement must not rewrite the original round.
printf 'codex-tuner-verdict: REQUEST_CHANGES %s\n' "$a" > "$work/round-1"
if publish "$work/round-1" --pr 2; then exit 1; fi
for field in host delivery review; do
  printf '%s: duplicate\n' "$field" >> "$spec"
  git add -- "$spec"; git commit -qm "ambiguous $field"
  printf 'codex-tuner-verdict: REQUEST_CHANGES %s\n' "$(git rev-parse HEAD)" > "$work/ambiguous"
  if publish "$work/ambiguous" --pr 2 2>"$work/error"; then exit 1; fi
  grep -q "duplicate or empty spec field $field" "$work/error"
  git show "$a:$spec" > "$spec"
done
git show "$a:$spec" | sed 's/delivery: draft/delivery: local/' > "$spec"
git add -- "$spec"; git commit -qm 'local scope'
printf 'codex-tuner-verdict: REQUEST_CHANGES %s\n' "$(git rev-parse HEAD)" > "$work/no-publish"
if publish "$work/no-publish" --pr 2 2>"$work/error"; then exit 1; fi
grep -q "reserves GitHub publication" "$work/error"
echo 'PASS exact-SHA rounds, delayed publication, lost response and local-only handoff'
