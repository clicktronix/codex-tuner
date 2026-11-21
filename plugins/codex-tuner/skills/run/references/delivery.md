# Delivery routes

Read the task and repository permissions first. A local handoff ends before push, board changes,
comments and PR/MR creation. If an already agreed destination is temporarily unavailable, keep the
verified candidate and its receipts locally. With `host: pending`, resolve the destination before
the first host operation.

## Hosted delivery

From the candidate checkout run `python3 "<plugin-root>/scripts/destination.py"`. Its three
tab-separated fields are the Git remote, hostname and project. `CODEX_TUNER_REMOTE` selects an
explicit remote. Resolve ambiguity before publishing and authenticate the CLI to that hostname.
Confirm the destination against the task. Use it explicitly for every push, fetch and forge call.
A PR in another fork needs its own confirmed source and target. The checked routes below assume
one project. Synchronize the agreed target and require the candidate to include its current tip.

Find a PR/MR for this project, source branch and target. Resume an existing request and reconcile
a merged request. Otherwise push the named task branch once and open at the authorized stage.
Use a draft for draft scope. Keep receipts under their original names when resuming.

### GitHub

Set `REPO="$FORGE/$PROJECT"`. Pass `--repo "$REPO"` to each `gh pr` command. Use
`git push "$REMOTE" "HEAD:refs/heads/$BRANCH"` and `gh pr create --draft --base "$TARGET"
--head "$BRANCH" --title "$TITLE" --body-file "$BODY" --repo "$REPO"` for a new draft.
Confirm the PR's head equals the verified candidate.

Publish the verifier's exact file as a PR comment with
`gh pr comment "$PR" --repo "$REPO" --body-file "$VERIFY_FILE"`. Pass the round's saved file
to the publisher. It reuses a published round on retry. New reviews must match the open PR, both projects, and the
source and target branches in the spec at the judged commit.

```bash
python3 "<plugin-root>/scripts/finish-review.py" "$ROUND_FILE" --pr "$PR" --spec "$SPEC"
```

Omit `--pr` to retain a local receipt. Under `ci: none:<reason>`, publish the substitute's command
and observed result from a file starting `codex-tuner-local-ci: <SHA> <command and result>`.
List the acceptance evidence and outstanding gaps. Run `gh pr ready` only when ready/open publication is
authorized. Draft-only runs leave the draft intact and identify any checks that await readiness.

For merge handoff run the command below with `--check-only`. For an authorized merge use the same
command without that flag. For a local review contract use `local` as the thread argument.

```bash
bash "<plugin-root>/scripts/merge.sh" --check-only --ci "$CI_MODE" "$PR" "$STRATEGY" "$SHA" "$THREAD" "$BASE" "$SPEC"
```

The gate checks the destination, exact candidate, target, review, latest attributable public
verdict and declared CI. New delivery contracts also require the published verification record.
Observe the PR's final state and merged head before cleanup. GitHub may queue a merge on a
protected branch. A queued request is pending until the forge reports `MERGED`.

### GitLab

Use `glab` when installed and authenticated to the confirmed GitLab host. Set
`PROJECT_ID=$(jq -rn --arg p "$PROJECT" '$p|@uri')` and `MR_API="projects/$PROJECT_ID/merge_requests/$IID"`.
Pass `--hostname "$FORGE"` to `glab api` and `--repo "https://$FORGE/$PROJECT"` to `glab mr`.

1. With publication authorized, push the named branch. Reuse its MR or open it using
   `glab mr create --draft --source-branch "$BRANCH" --target-branch "$TARGET"` with the selected
   project, title and description. Read the MR by API. Check `state=opened`, source and target project
   IDs, both branches and `sha=$SHA`. A draft stays a draft under draft-only authority.
2. In Claude mode run `scripts/check-review.sh "$THREAD" "$SHA" "$BASE" "$SPEC"` on the clean approved
   candidate. Use the round's local receipt from the run; for a blocking verdict retain the SHA
   captured before dispatch. Publish the verification file and verdict as MR notes from files.
   Use `jq -Rs '{body:.}' < "$FILE" | glab api "$MR_API/notes" --hostname "$FORGE" --method POST --input -`.
   Give each verdict note the first line `codex-tuner-verdict: <verdict> <SHA>` and a separate
   `<!-- codex-tuner-round: <claim or unique local round ID> -->` line. On retry read all notes first
   and reuse the same author's matching round. Preserve the judged SHA when the MR advances.
3. Mark a draft ready only when authorized. Read all pages of MR notes and select the authenticated
   author's latest verdict for this SHA, ordered by creation time and ID. Require APPROVE and the
   corresponding verification evidence. Read the MR's current
   [approval state](https://docs.gitlab.com/api/merge_request_approvals/) and respect required people,
   unresolved threads and merge checks. A pending required approval remains a human handoff.
4. Read `head_pipeline`. Require a successful target-project pipeline on the exact head. For a
   merged-results pipeline, fetch its merge ref and prove the pipeline commit's second parent is the
   candidate. Under `none:<reason>`, require an absent pipeline and the author's exact-SHA
   `codex-tuner-local-ci` note. Existing failed, pending or skipped pipelines remain pending delivery.
5. Fetch the spec target using the selected remote. Require its current tip to be an ancestor of
   the candidate. Check the project's squash policy permits the spec's strategy. Re-read the MR head,
   target, CI, approvals and notes immediately before merge. Pass the exact head and explicit squash
   setting in the [merge API](https://docs.gitlab.com/api/merge_requests/#merge-a-merge-request).

   ```bash
   glab api "$MR_API/merge" --hostname "$FORGE" --method PUT -f sha="$SHA" -F squash="$SQUASH"
   ```

   Set `SQUASH=true` for squash and `false` for merge. A handoff stops before this write and retains
   the complete checks above. Confirm the MR reports `merged` before reconciling the tracker.

## Local Git target

For a local handoff, preserve the user's checkout and return the evidence. A local **merge** is a
separate task with `host: local`, `delivery: merge`, `merge: ff` and `ci: none:<reason>`.
Use a clean committed candidate and its declared target. Verify as usual and run the named local
CI substitute. Save each record on the judged commit with
`git notes --ref=codex-tuner append -F "$FILE" "$SHA"`. The records are the verifier's exact-SHA
file, each round's verdict line, and `codex-tuner-local-ci: <SHA> <command and result>`.
Keep a repeated note for a given receipt from superseding a newer judgement.

Use the local gate below for a preflight. Omit `--check-only` only when merge is authorized.
The gate checks the local target and notes, runs the companion check when declared, and
fast-forwards a clean target worktree or atomically advances an unchecked-out ref. A dirty target
stays with its owner.

```bash
python3 "<plugin-root>/scripts/local-merge.py" --check-only "$SHA" "$THREAD" "$BASE" "$SPEC"
```

Confirm the target ref equals the reviewed SHA after the merge. This route performs no remote write.
