---
name: run
description: Use only when explicitly invoked to implement a committed spec or a concrete task through tests, exact-candidate review, required CI, merge, and cleanup.
---

# Run Task

Parse `[--auto] <spec-path | concrete task>`. When a committed spec exists, it is authoritative.
Without one, derive and commit the short contract described below before implementation.

`--auto` authorizes task-scoped commits, push, PR creation/update, and merge after every gate passes.
It does not authorize deploy, publish, migration, force-push, destructive data operations, or work
outside the task. It changes workflow policy, not client persistence: for overnight work the user
must start Codex `/goal` before invoking this skill.

## 1. Establish the contract

Read repository instructions, `../task-flow/SKILL.md`, the spec when supplied, relevant code and
tests, and current dependency docs when required. Verify the task branch and target. Refuse `--auto`
when the spec says `auto_ready: no` or an unresolved human-only decision remains.

For missing detail under `--auto`, choose the safest in-scope reversible option from repository
evidence and record the choice. Stop only for missing authority, secrets, irreversible operations,
or a decision that would materially change scope. Do not turn ordinary implementation questions into
user interviews. Existing authorization covers routine checks and successful reviews: they do not
need another confirmation. Batch related pending decisions into one concise request and continue
the available work meanwhile; do not wait for a finding count or claim a blocked outcome complete.

Publish a native plan before changing files. Include contract creation when needed, implementation
units, verification, acceptance, candidate finalization, review, PR/CI, merge, and cleanup. Keep it
current throughout the run; do not create a parallel journal or run-state file. Goal mode and the
native plan own persistence and status.

When no committed spec was supplied, use the contract shape in `../spec/SKILL.md`. Create and commit a
short task contract on the task branch. In attended mode, present it once for approval; under `--auto`,
resolve ordinary in-scope choices from repository evidence. Use that tracked path as the spec for
every later review and merge gate.

## 2. Implement and prove

Work one dependency-safe unit at a time. Parallelize only independent code-writing units with
non-overlapping ownership; the parent integrates them into one candidate. Testing decisions, review
decisions, delivery, and merge remain sequential.

For behavior changes:

1. Run the named failing check and confirm the expected semantic failure.
2. Implement the smallest systemic fix within scope.
3. Run targeted, full, static/build, runtime, and acceptance checks from the contract.
4. Run the named negative proof when false green is otherwise plausible. Do not invent mutation work
   for every slice.
5. Read the complete diff and account for generated or formatter changes.

A failing fixture, syntax error, unavailable service, or unrelated baseline failure is not proof of
the requested RED. Establish whether a failure is pre-existing from reachability and the task-base
diff, not merely from file age.

## 3. Freeze the candidate

Stage explicit paths only, inspect the staged diff, and commit using repository conventions. Require
a clean worktree and record the full candidate SHA, base SHA, spec path (or `none`), and PR number.

Any later code or test edit creates a new candidate and invalidates tests affected by the edit,
acceptance, required review, public verdict, CI, and merge readiness. Re-run only the evidence the
change can invalidate; do not restart unrelated advisory reviews as a ritual.

## 4. Review proportionally

Run the repository's `$code-review` once on the first clean candidate, passing the fixed base and
committed spec explicitly. Validate its findings against the spec, source, and a concrete failure;
fix valid findings and refute optional or out-of-scope suggestions instead of expanding the task.

Add one high-effort owner review only when the candidate:

- touches authentication, authorization, secrets, cryptography, destructive data, migrations,
  public or persisted contracts, money, infrastructure, release, or security-sensitive input;
- changes at least 15 production files or 500 production lines;
- spans repositories/services or changes a major architectural boundary.

That deep pass covers correctness/spec, architecture/systemic effects, security/data, and
testing/operability. It is one coordinated review of one immutable candidate; do not fan it into a
large agent swarm. Small ordinary changes pay only the normal review.

After advisory findings are settled, obtain the authoritative external review:

```text
$codex-cc-triage:claude-review --required --base <base-sha> --spec <repo-relative-spec> --thread <task-thread> --cap 5 Review the complete candidate for correctness, architecture, security/data, and testing/operability. End with the required verdict.
```

Publish every completed external verdict immediately, before editing the candidate:

```bash
gh pr review <pr> --comment --body "codex-tuner-verdict: <APPROVE|REQUEST_CHANGES> <candidate-sha>"
```

On `REQUEST_CHANGES`, validate findings, fix only valid in-scope issues, rerun affected evidence,
commit a new candidate, and continue the same review thread. If every finding is refuted with a
concrete `file:line` or explicitly deferred, the SHA stays unchanged but a fresh required round must
approve it. Never reset a capped thread to seek an easier verdict.

**At the cap, stop paid review attempts and delivery — not the work.** Continue the safe remaining
fixes, keep the candidate stable, and report the missing approval once, in one request, together with
any other pending decision. Missing, stale, unavailable, diverged or capped review blocks merge; it
does not end the run.

## 5. Deliver through the checked boundary

Push and create or update the PR for each participating repository. Require candidate SHA = pushed
SHA = current PR head. Observe CI in the mode the spec declares — `required`: the target's required
checks; `any`: every check reported on the head, at least one; `none:<reason>`: no hosted checks, and
the local substitute recorded first with
`gh pr comment <pr> --body "codex-tuner-local-ci: <candidate-sha> <what ran, and what it returned>"`.
Pending, skipped, stale, cancelled, billing-blocked or red is not green in any mode, and `none` never
outranks a check that ran. If observation contradicts the spec, correct its `ci:` mode before review
rather than picking a mode at the merge boundary. Check every Definition of Done item by name.

Use the spec's merge strategy, its `ci` mode verbatim, and the same required-review thread:

```bash
bash "<plugin-root>/scripts/merge.sh" --ci <mode> <pr> <squash|merge> <candidate-sha> <review-thread> <base-sha> <spec-path>
```

Resolve `<plugin-root>` as two directories above this skill directory. `merge.sh` independently
re-reads the companion approval, public verdict, PR head, and CI under the declared mode, then uses
GitHub's atomic head pin. Do not replace it with raw `gh pr merge` for a codex-tuner run.

Without `--auto`, stop before the first push or PR creation and again before merge. Under `--auto`,
continue when the checked boundary passes. After confirmed `MERGED`, reconcile the tracker/spec,
switch to the literal target, pull `--ff-only`, and remove only clean worktrees and proven-merged
branches.

## Hard stops

- Scope or authority required beyond the contract.
- Unresolved human-only acceptance under `--auto`.
- Red or missing verification, review, CI under the declared mode, or DoD evidence — a hard stop for
  **delivery**; safe in-scope work continues and the gap is reported once.
- Dirty or moved candidate, unexplained files, stale approval, or moved PR head.
- Deploy/publish/migration, force-push, bypass flags, broad staging, or direct target commits.

Report the completed outcome first, then candidate/PR/CI/review evidence, deferred findings, and
cleanup. Never claim CI, approval, or merge from an older SHA.
