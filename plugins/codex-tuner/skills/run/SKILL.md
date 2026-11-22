---
name: run
description: Implement or resume an authorized task from its spec, verify the actual changes, review the candidate and carry delivery through the permitted stage.
---

# Run a task

Use `[--auto] [--local-only] [spec path or task]`. Resume the current task from its spec,
branch, open PR/MR and existing review thread. If the change already landed, reconcile the
result. A request for planning or review alone ends with that deliverable.

## 1. Establish the contract

Read the applicable repository rules, [task flow](../task-flow/SKILL.md), the spec and its affected
code and consumers. Check the target, branch and delivery scope in each participating checkout.
When the user asked to implement a task without a spec, write the short [task contract](../spec/SKILL.md)
on the task branch and proceed with decisions already supplied. Ask only for a consequential missing
decision. When commits are reserved, use a working spec and `--local-only`.

Use the client's native plan for substantial work. Track units, acceptance, verification, review
and the authorized handoff there. Use Goal mode when the user requested it and the host provides
it. An ordinary run can finish in the current session. Existing task and repository permissions
govern commits, remote writes, board changes, merge and deployment independently.

| Delivery scope | Last authorized action |
| --- | --- |
| `local` or `--local-only` | Implement, test and review locally. Preserve uncommitted changes when commits are reserved. |
| `draft` | Push the task branch, open or update its draft PR/MR, attach authorized evidence, and leave it a draft. |
| `pr` | Deliver the requested PR/MR, including readiness and observing applicable CI. Hand over merge readiness. |
| `merge` | Recheck the route and merge the verified head when the user authorized merge. |

An explicit PR request covers its task branch push and ordinary evidence comments. Use `--auto`
only for requested unattended delivery. It can authorize merge within the agreed scope. It grants no
deployment, publishing, migration, force-push or destructive data operation. A narrower
request or repository rule wins. A planned stage describes the intended destination. Only the
user's authorization permits widening it. For `auto_ready: no`, resolve the listed prerequisites
within the current task and recheck readiness before the stage that depends on them.
Keep doing local work when authentication, a remote,
a human acceptance step or publication permission blocks a later stage. Ask once when that step
is necessary and the user has not already reserved it for themselves.

## 2. Implement and prove

Run the check that exposes the original behavior. Confirm the expected failure, implement the
change and run the checks that exercise it. For docs or configuration, use an observable baseline.
Read the whole diff, including untracked paths and generated outputs. Follow
[verification](../../references/verification.md) for negative proof and acceptance.

Use independent units with disjoint ownership when delegated work is authorized and useful.
The parent integrates and verifies their combined result. For long checks, wait on the same job
and inspect its result. Follow [task resources](../../references/resources.md) for previews and
containers. Run heavy checks through `<plugin-root>/scripts/heavy.sh` as its
[heavy checks](../../references/resources.md#heavy-checks) section describes; an e2e suite takes
`--weight 2`.

## 3. Verify the actual candidate

Inspect tracked, staged and untracked changes. When commits are permitted, stage the intended
paths, review the staged diff and commit on the task branch. Finalize the spec path before
pinning review. Record the base, full HEAD and tree of the clean candidate. When offline,
use the known base and record that target synchronization is pending.

Run [verify-feature](../verify-feature/SKILL.md) on that candidate or the actual uncommitted
worktree. Pass the spec, base, checks already run, the working directory and a private scratch
file outside the checkout. Read the resulting evidence. Preserve every unproved criterion
and any user decision about it. Reuse observations while their inputs are unchanged. A fix
needs verification of affected criteria and a record identifying the new candidate.

## 4. Review proportionally

Review the complete task diff for the agreed outcome and repository standards. Use
[deep-review](../deep-review/SKILL.md) for sensitive changes, a large production diff, or a
cross-service boundary. Use the ordinary repository review for the rest. If a reviewer is
unavailable, do the local review yourself. Validate findings at their source and consumers,
fix regressions within scope and retain evidence for refuted findings.

For a dirty or local-only handoff, return the base, changed and new paths, acceptance evidence,
findings and the next reserved action. A worktree review can include uncommitted files.
Only a clean commit can receive an exact-SHA approval. When publication is reserved but
committed-candidate review is authorized, record that review locally without creating a PR.

## 5. Review rounds and delivery

Use the spec's review owner. `review: claude` (the default for older specs) uses the authorized
read-only companion. `review: local` uses the owner's exact-candidate judgement when the owner
selected that mode. A missing installation or exhausted review rounds leave required approval pending.

For Claude review, keep the thread, literal initial base and tracked spec fixed. Pass the evidence
file and gaps with the request. Omit `--cap` to use the saved round limit, or the companion's
default on a new thread. Pass a smaller limit when agreed.

```text
$codex-cc-triage:claude-review --required --base <base-sha> --spec "<spec-path>" --thread <thread> Review the complete candidate and its acceptance evidence.
```

Finish each round before editing, committing or pushing a fix. Record its result with the
companion. Save the receipt in a private directory under a distinct name per claim. An approval
receipt is the output of `<plugin-root>/scripts/check-review.sh "$THREAD" "$SHA" "$BASE" "$SPEC"`.
For validated blocking findings (also at the cap), or a local review decision, write
`codex-tuner-verdict: <APPROVE|REQUEST_CHANGES> <full judged SHA>` to that round's file.
An incomplete round has no publishable verdict. Keep the same file on retry.

Read the [delivery routes](references/delivery.md) before the first remote write. Publish the
receipt immediately when allowed. When the forge is unavailable, keep it, continue safe fixes,
and retry against the original SHA before the next push. Resolve confirmed findings, reverify
and review the next clean candidate. Refuting or waiving every finding on the same SHA still
requires a fresh decision. When the review rounds run out, continue safe work and report the missing
approval once. After the owner agrees to more rounds, renew the same thread through the companion's
`review-state.sh renew "$THREAD" --by "$OWNER"`.

Before publication and merge, synchronize the target. If it advanced, integrate it and refresh
affected evidence. The integration merge takes a normal review round. Follow the selected route
through the last permitted action.

A coupled outcome is delivered as a set. Verify combined acceptance from the primary spec,
check each route before the first merge, and confirm each rollout prerequisite with its named
command. On a partial delivery, name the landed and pending candidates. After an observed merge
follow [task flow](../task-flow/SKILL.md) for the correct target, tracker and cleanup.
