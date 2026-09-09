---
name: spec
description: Use only when explicitly invoked to turn an issue or rough task into one approved, committed specification for codex-tuner run.
---

# Specify Task

Create one durable contract for `$codex-tuner:run`. This skill owns discovery and readiness; `run`
owns implementation and delivery. Do not implement or merge here.

## Understand the task

Read repository instructions, the issue, architecture records, relevant code, tests, callers, and
consumers before asking questions. Fetch current primary documentation through the repository's
required documentation mechanism when versioned dependencies are involved.

Resolve:

- the observed problem or desired outcome;
- ownership, boundaries, data/control flow, and affected consumers;
- scope and rejected alternatives;
- acceptance evidence and exact verification commands;
- the first failing regression check, or an honest non-code baseline;
- branch, target, PR, merge strategy, CI, tracker, and any external dependency.

Do not ask for information already in the repository. Use `$grilling` only when a large or genuinely
unclear task still has product decisions after this reading. Use `$domain-modeling` only when the
task changes durable vocabulary or context boundaries. Ordinary work should not pay either cost.

## Create the branch

Read `../task-flow/SKILL.md`. Resolve and fetch the integration target. If currently on it, create the
task branch; otherwise verify the current feature branch belongs to this task and is not already
merged. Never commit the spec to the integration branch.

## Draft the contract

Use `wiki/PLANS/YYYY-MM-DD-<slug>.md` when `wiki/` exists, otherwise
`docs/PLANS/YYYY-MM-DD-<slug>.md`:

```markdown
# <title>

**Goal:** <what becomes true>
**Issue:** #N | none
**Architecture:** <owner, boundaries, data/control flow, rejected alternatives>

## Scope
- In: <owned behavior and consumers>
- Out: <explicit exclusions>

## Acceptance criteria
- [ ] [machine] <criterion> — checked by: <exact command or tool step>
- [ ] [eyes] <criterion> — human step: <step>; machine replacement: <step|none>; waiver: <user/date|none>

## Verification
- First failing check: <command>; expected failure: <specific assertion or error>
- Targeted checks: <commands>
- Full regression: <command>
- Static/build checks: <commands | not applicable — reason>
- Runtime environment: <services, browser/device, fixtures, data, credentials boundary>
- Negative proof: <mutation or baseline that distinguishes a false green | not applicable — reason>

## Implementation outline
1. <owned paths> — <independently verifiable behavior>

## Definition of Done
- [ ] Acceptance and verification above pass
- [ ] Complete diff is accounted for; no unexplained files remain
- [ ] Required reviews approve the exact clean candidate
- [ ] PR head equals the reviewed SHA and CI passes on it under the declared `ci` mode
- [ ] Merge and tracker/branch/worktree cleanup are reconciled

## Delivery
branch: <task branch>
target: <integration branch>
merge: squash|merge
auto_ready: yes|no — <reason when no>
ci: <mode> — <the checks, and how to observe them>
    required   the target branch has required checks on GitHub (the default; strongest)
    any        CI runs here but nothing is required — every reported check must pass
    none:<why> no hosted checks; the local substitute is recorded on the PR before merge
tracker: gh|none
```

Choose `ci` from what the repository actually does, not from the default: inspect branch protection
and the workflows that attach to a candidate. `run` passes the mode verbatim to `merge.sh`.

Use `[eyes]` only for irreducible human judgement. `auto_ready: yes` requires a defined PR per
participating repository, complete verification commands, a nonblank `ci` mode, and a machine
replacement or dated waiver for every `[eyes]` item. A coupled outcome may span repositories; each
candidate then carries its own review and CI contract. Documentation-only work may replace RED or
mutation with a concrete baseline and diff check.

Split work into multiple specs only when it needs multiple PRs, repositories, or independently
reviewed delivery phases. The implementation outline is guidance for Codex's native plan, not a
second plan file or a custom state machine.

## Confirm and commit

Present the decisions, scope, checks, and implementation outline once. Ask the user to approve the
contract; revise if needed. After approval, create or update the issue, write the spec, link issue and
spec both ways, inspect the full diff, and commit only the intended spec and any required domain
artifacts using repository conventions.

Report the spec path, branch, target, and next command:

```text
$codex-tuner:run docs/PLANS/2026-08-31-example.md
```

For unattended execution, tell the user to enter Codex Goal mode with `/goal`, then invoke
`$codex-tuner:run --auto <spec>`. A skill cannot switch the client into Goal mode itself.
