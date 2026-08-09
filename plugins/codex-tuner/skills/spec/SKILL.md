---
name: spec
description: Use only for explicit $codex-tuner:spec invocations. Turn an issue, ticket, or rough coding task into a committed executable specification with explicit Definition of Ready, test plan, acceptance, and Definition of Done.
---

# Specify Task

Produce a committed spec that `$codex-tuner:run` can execute without reopening product or verification
decisions. This skill owns discovery and readiness; `run` owns delivery. Explicit invocation authorizes
creating the task branch, committing the spec and required domain-model artifacts, and linking its
tracker issue, but not implementation or merge.

Resolve `<plugin-root>` as two directories above this skill and run:

```bash
bash "<plugin-root>/scripts/execute-task/prereq-check.sh"
```

## Read before asking

Read, in order:

1. nearest `AGENTS.md` files, repository docs, and existing `CONTEXT.md` / `CONTEXT-MAP.md` vocabulary;
2. the issue and repository task-flow configuration;
3. architecture records, code, tests, callers, and consumers the task can affect;
4. current primary docs for versioned libraries, APIs, CLIs, and cloud services through the
   repository-required documentation mechanism.

Do not ask for information already present.

## Grill and model

Invoke `$grilling` before drafting. Ask one decision question at a time, include a recommended answer,
and wait for the user. Continue until answers stop changing the draft; do not implement while grilling.

Invoke `$domain-modeling` when the task changes domain vocabulary, context boundaries, or a durable
architectural trade-off. Challenge the model during grilling, then write only the glossary, context
map, or ADR artifacts the skill actually requires.

Resolve before calling the task ready:

- observed problem or desired user outcome;
- architecture ownership, data/control flow, and affected consumers;
- explicit scope and rejected alternatives;
- acceptance evidence;
- first failing regression check or honest non-code baseline;
- targeted/full/static/runtime checks, environment, fixtures, data, and external dependencies.

A pending `TBD`, “as appropriate”, unknown test command, or unstated expected failure means the spec
is not ready.

## Define acceptance and delivery shape

Tag every criterion:

- `[machine]`: an exact command or browser-driving step decides it;
- `[eyes]`: human judgement is irreducible; name the concrete human verification step.

Every `[eyes]` item records its human step, machine replacement (or `none`), and dated waiver (or
`none`). An item with neither replacement nor waiver requires `auto_ready: no`: HITL `run` stops for
the human step and `--auto` rejects it.

More than one PR, more than one repository, or independently reviewed phases require an epic with
native sub-issues and one spec per sub-issue.

## Create the task branch

Read `<plugin-root>/skills/task-flow/SKILL.md`. Resolve and fetch the integration target from
repository policy or the remote default branch. If currently on the target, create the task branch. If
already on a feature branch, verify it belongs to this task and its PR is not merged. Never commit the
spec directly to the target. The branch created here is the branch `run` continues.

## Write and commit the executable contract

Write `<plans-root>/PLANS/YYYY-MM-DD-<slug>.md`, using `wiki/` when present and `docs/` otherwise:

```markdown
# <title>

**Goal:** <what becomes true>
**Issue:** #N | none
**Architecture:** <ownership, data/control flow, and rejected alternatives>

## Definition of Ready
- [x] Problem/baseline: <current failure or missing behavior with evidence>
- [x] Scope: <owned modules and consumers>; out of scope: <boundaries>
- [x] Acceptance: every criterion below has a deciding check
- [x] Test plan: commands, expected first failure, environment, and data are explicit
- [x] Delivery: one branch, one PR, target, tracker, and CI source are explicit

## Acceptance criteria
- [ ] [machine] <criterion> — checked by: <exact command or tool step>
- [ ] [eyes] <criterion> — checked by: <human step>; machine replacement: <exact check|none>; waiver: <user/date|none>

## Test plan
- Regression test: <path and test/assertion to add or existing failing check>
- First failing check: <exact command>; expected failure: <specific assertion/error proving the gap>
- Targeted checks: <exact commands>
- Full regression: <exact command>
- Static/build checks: <typecheck/lint/build commands or `not applicable — reason`>
- Runtime/acceptance environment: <services, browser/device, fixtures, data, credentials boundary>
- Negative/mutation proof: <how the test is shown to fail without the fix>

## Implementation tasks
1. <owned file paths> — <independently verifiable change and reason>

## Definition of Done
- [ ] Regression check was observed failing for the expected reason before the fix
- [ ] Targeted, full, static/build, runtime, and acceptance checks passed as specified
- [ ] Complete diff and formatter/autofix output were read; no unexplained files remain
- [ ] Candidate passed owner, Matt, and Claude review on its exact SHA/tree
- [ ] PR head equals the reviewed SHA and required CI is green on that SHA

## Completion and reconciliation
- [ ] PR is merged with the configured method
- [ ] Spec/archive, issue/board, target sync, branches, and worktrees are reconciled

## Run config
branch: <current task branch>
target: <integration branch>
merge: squash|merge
auto_ready: yes|no — <reason when no>
ci: <exact command or check source>
cheap_gate: <exact command>
target_test: <exact command>
full_test: <exact command>
tracker: gh|none
board: <project title + owner | none>
```

For documentation-only or mechanical work, `First failing check` and `Negative/mutation proof` may say
`not applicable` only with a concrete reason and alternative baseline/diff check.

Set `auto_ready: yes` only for one PR with complete DoR, nonblank `ci`, `target_test`, and `full_test`,
and a machine replacement or waiver for every `[eyes]` item. Only explicit
`$codex-tuner:run --auto <spec>` requests unattended execution.

Inspect the diff, stage only the spec and domain-model artifacts produced by this task, and commit with
a Conventional Commit. Link the issue and spec both ways when `tracker: gh`; explain `tracker: none`.

## Hand off

Report spec path, current branch, target, and one suitable command. Offer `--auto` only when ready:

```text
$codex-tuner:run docs/PLANS/2026-07-31-thing.md
$codex-tuner:run --auto docs/PLANS/2026-07-31-thing.md
```

Verify DoR, deciding checks, explicit task ownership, exact-candidate DoD, branch/PR ownership, the
committed spec, and tracker links before handoff.
