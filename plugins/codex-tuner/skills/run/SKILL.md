---
name: run
description: Use when the user explicitly invokes $codex-tuner:run with a committed spec to execute it end to end through implementation, acceptance, review, pull request, current-SHA CI, merge, and cleanup. Without --auto, stop at every phase boundary; with --auto, proceed unattended through merge only when the spec is explicitly auto-ready and every gate is green.
---

# Run Specification

Parse the invocation as `[--auto] <spec-path>`. No spec path means stop; never reconstruct one from
chat. Explicit `--auto` authorizes task-scoped commit, push, PR creation/update, and merge to the spec's
target after green CI. It never authorizes deploy, publish, migration, force-push, or extra scope.

Resolve `<plugin-root>` as two directories above this skill. Read:

- the committed spec;
- `<plugin-root>/workflow-contract.json`;
- `<plugin-root>/references/tiering.md`;
- `<plugin-root>/skills/task-flow/SKILL.md`;
- `.codex/execute-task.md` only for stable repo defaults omitted by the spec.

The spec wins on every field it supplies.

## Phase protocol

At the top of every phase after Phase 0, before any other action:

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

At each phase end, persist literal values a later phase would otherwise re-derive:

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" append <literal-run-id> "<phase result with literal branch/SHA/PR/check values>"
```

When `--auto` is absent, report the completed phase and exact next phase, then stop until the user says
to continue. Do not re-litigate the spec. With `--auto`, continue unless a hard stop fires.

## Phase 0 — open

1. Derive one stable run ID from the spec slug using only lowercase ASCII letters, digits, `.`, `_`,
   and `-`; keep it unchanged across restarts. Resolve literal `branch`, `target`, and `auto_ready`.
   Confirm the current branch matches `branch`, is not `target`, contains the committed spec, and has
   no merged PR. For a legacy spec without `branch`, derive and journal ownership unambiguously; never
   create a second branch blindly.
2. Require every `[eyes]` item to name `checked by`, `machine replacement`, and `waiver`. Refuse
   `--auto` unless the spec says `auto_ready: yes`, CI is nonblank, the scope is one PR, and every
   `[eyes]` item has a replacement or waiver. `auto_ready: no` is authoritative.
3. Require a clean baseline and open the journal:
   ```bash
   bash "<plugin-root>/scripts/execute-task/preflight.sh" <literal-run-id> <literal-target> --expected-branch <literal-branch>
   ```
4. Journal the spec path, Run config, acceptance criteria verbatim, branch, target, and base SHA. Move
   the configured card to In Progress after recording its prior status.

Apply the phase boundary.

## Phase 1 — implement

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Treat the Tasks list as the complete scope. Decompose by independently verifiable units
and assign reasoning effort from `references/tiering.md`. Independent units may run concurrently
only with isolated worktrees; dependent units run in order. Before accepting delegated output, read its
complete diff, run the scoped cheap gate, and check its acceptance criteria.

Anything outside Tasks is a finding, not a licence. Journal it and remain in scope. Apply the boundary.

## Phase 2 — cheap gate

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Run `cheap_gate`; fix task-introduced failures before proceeding. Establish an alleged
pre-existing failure against the task base. After formatter or `--fix`, read its diff and re-run both
typecheck and lint. Journal exact commands/results and apply the boundary.

## Phase 3 — acceptance

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Drive every `[machine]` item with its named command or browser step, then run the full
`test` as a regression net. Resolve `[eyes]` only as recorded: drive its replacement; journal its dated
waiver; or, in HITL, present the human step and stop until the user reports the result. An unresolved
item is forbidden under `--auto`. Journal each criterion separately and apply the boundary.

## Phase 4 — review

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Read small-diff thresholds and sensitive surfaces from `workflow-contract.json`; use
`references/tiering.md` only for effort selection.

1. Review the complete committed, staged, unstaged, and untracked change set yourself.
2. Unless the diff is within both contract-defined small-diff thresholds and confidently
   non-sensitive, obtain an independent complete-diff review using an available isolated reviewer. On
   sensitive work, keep the main review at `xhigh` and never delegate judgement blind.
3. Validate each finding against live code. Mark it fixed, refuted with `file:line`, or deferred to an
   issue. Reviewer approval supports judgement; it never replaces tests.
4. Re-run the cheap gate and affected acceptance paths after fixes.

Journal final review state and apply the boundary.

## Phase 5 — finalize the branch

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Tick Tasks and criteria, record shipped/deferred scope, archive a completed spec to
`<plans-root>/ARCHIVE/PLANS/` in this branch, and run required local checks against the final tree.
Apply the boundary. In HITL mode, continuation authorizes Phase 6's commit/push/PR actions, not merge.

## Phase 6 — commit, push, PR, and CI

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

1. Inspect full status and diff. Stage only explicit task paths:
   ```bash
   git add -- <path-1> <path-2>
   git diff --cached --check
   ```
2. Run the guard after staging and inspect the staged diff:
   ```bash
   bash "<plugin-root>/scripts/execute-task/guard-artifacts.sh" <literal-run-id>
   git diff --cached
   ```
3. Commit conventionally, push with tracking, find or create the PR with a literal title, then journal
   its literal number and pushed SHA. The prepared PR body links the issue/spec and lists scope,
   verification, and limitations:
   ```bash
   git commit -m "<type>: <imperative summary>"
   git push -u origin <literal-branch>
   gh pr view <literal-branch> --json number,url,headRefOid,baseRefName || gh pr create --base <literal-target> --head <literal-branch> --title "<literal-title>" --body-file <prepared-body-file>
   ```
4. Confirm the PR base equals the literal target and its remote head equals the journaled SHA. Run or
   observe required CI on that SHA. Missing, skipped, stale, or red checks are not green.

In HITL mode, show the PR and CI and stop before merge. In `--auto`, continue only on green required CI.

## Phase 7 — merge and clean up

```bash
bash "<plugin-root>/scripts/execute-task/journal.sh" resume <literal-run-id>
```

Re-run the guard. Verify target, reviewed remote SHA, required CI, acceptance, and review
state. Merge automatically only under `--auto`; otherwise require separate explicit confirmation.

Confirm the PR is actually `MERGED`, then sync the card: `Closes`/`Fixes` → Done; `Refs` → remain In
Progress. Post-merge board failures are journaled, not terminal. Before leaving the owned task branch,
append the `MERGED` state, board result, and literal cleanup plan. Then switch to the literal target,
pull with `--ff-only`, and remove only clean worktrees and branches proven merged. Do not append to the
branch-owned journal after switching targets.

## Hard stops

- Red cheap gate, acceptance, full test, review, or required CI.
- Unresolved `[eyes]` criteria or `auto_ready: no` under `--auto`.
- Scope outside the spec or conflicting user work.
- Deploy, publish, migration, or another production action. After merge, only board/spec/branch/
  worktree reconciliation described in Phase 7 is authorized.
- Force-push, `--no-verify`, broad staging, unsafe amend, or commit to target.

Report criteria with their checks, review disposition, PR/current-SHA CI, merge state, deferrals, and
journal path. Never claim hosted CI or merge from an older SHA.
