---
name: spec
description: Use only for explicit $codex-tuner:spec invocations. Turn an issue, ticket, or rough coding task into a committed, machine-checkable specification after repository and documentation research.
---

# Specify Task

Produce a committed spec that `$codex-tuner:run` can execute without re-opening product decisions.
This skill owns questions; `run` owns delivery. Explicit invocation authorizes creating the task branch,
committing the spec and domain-model artifacts, and creating or updating its tracker issue, but not
implementation or merge.

Resolve `<plugin-root>` as two directories above this skill and verify companion skills before doing
task work:

```bash
bash "<plugin-root>/scripts/execute-task/prereq-check.sh"
```

## Read before asking

Read, in order:

1. The nearest `AGENTS.md` files, repository documentation, and existing `CONTEXT.md` or
   `CONTEXT-MAP.md` domain vocabulary.
2. The referenced issue and repo-specific task-flow configuration.
3. The code, tests, consumers, and architecture boundaries the task touches.
4. Current primary documentation for versioned libraries, APIs, CLIs, and cloud services, using the
   documentation mechanism required by the repository.

Do not ask for information already available there.

## Grill and model

Invoke `$grilling` before drafting. Ask one decision question at a time, include a recommended answer,
and wait for the user's answer. Continue until the user confirms shared understanding; do not implement
while grilling.

Invoke `$domain-modeling` when the task introduces or changes domain vocabulary, context boundaries, or
a durable architectural trade-off. Challenge the model during grilling, but do not write its glossary
or ADR changes until the task branch below is selected. Then apply only the artifacts the skill calls
for; do not create them when the domain model did not change. A pending `TBD`, "as appropriate", or an
unstated first failing test means the spec is not ready.

## Define acceptance and scope

Tag each criterion:

- `[machine]`: an exact command or browser-driving step decides it.
- `[eyes]`: human judgement cannot be reduced to an observable check; name the concrete human step.

Every `[eyes]` item records its human step, machine replacement (or `none`), and dated waiver (or
`none`). An item with neither replacement nor waiver is valid only with `auto_ready: no`: HITL `run`
will stop for that human step, while `--auto` must reject the spec. More than one PR, more than one
repository, or independently reviewed phases require an epic with sub-issues and one spec per sub-issue.

## Create the task branch

Read `<plugin-root>/skills/task-flow/SKILL.md`, where `<plugin-root>` is two directories above this
skill. Resolve the integration target from repository policy, falling back to the remote default branch,
and fetch it. If currently on the target, create the task branch now. If already on a feature branch,
confirm it belongs to this task and its PR is not merged. Never commit the spec directly to the target.

The branch created here is the branch `run` continues. Do not create a second branch for the same spec.

## Write and commit

Write `<plans-root>/PLANS/YYYY-MM-DD-<slug>.md`, using `wiki/` when present and `docs/` otherwise:

```markdown
# <title>

**Goal:** <what becomes true>
**Issue:** #N | none
**Architecture:** <approach and rejected alternatives>

## Acceptance criteria
- [ ] [machine] <criterion> — checked by: <exact command or tool step>
- [ ] [eyes] <criterion> — checked by: <human step>; machine replacement: <exact check|none>; waiver: <user/date|none>

## Tasks
1. <file path> — <change and reason>

## Out of scope
<explicit boundaries>

## Run config
branch: <current task branch>
target: <integration branch>
merge: squash|merge
auto_ready: yes|no — <reason when no>
ci: <exact command or check source>
cheap_gate: <exact command>
test: <exact command>
tracker: gh|none
board: <project title + owner | none>
```

Set `auto_ready: yes` only for one PR with nonblank CI and a machine replacement or waiver for every
`[eyes]` item. This records capability; only invoking `$codex-tuner:run --auto <spec>` requests
unattended execution.

Inspect the diff, stage only the spec and any `CONTEXT.md`, `CONTEXT-MAP.md`, or ADR files produced by
this task's domain-modeling pass, and commit them with a Conventional Commit. Create or update the issue
so it and the spec link to each other when `tracker: gh`; with `tracker: none`, record why there is no
issue.

## Hand off

Report the spec path, current branch, target, and one suitable command. Offer `--auto` only when
`auto_ready: yes`:

```text
$codex-tuner:run docs/PLANS/2026-07-31-thing.md
$codex-tuner:run --auto docs/PLANS/2026-07-31-thing.md
```

Verify that every criterion names its deciding check, no executor-owned product decision remains, the
spec is committed on its task branch, and the issue links both ways or `tracker: none` is explained.
