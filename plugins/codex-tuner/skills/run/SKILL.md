---
name: run
description: Use only for explicit $codex-tuner:run invocations with a committed spec. Publish a visible plan, implement, prove tests, review an immutable candidate, verify current-SHA CI and DoD, then merge and reconcile.
---

# Run Specification

Parse `[--auto] <spec-path>`. No path means stop; never reconstruct a spec from chat. Explicit
`--auto` authorizes task-scoped commit, push, PR creation/update, and merge to the named target after
every gate passes. It also authorizes the task-scoped read-only Claude review. It never authorizes
deploy, publish, migration, force-push, or extra scope.

Resolve `<plugin-root>` as two directories above this skill. Read the committed spec,
`workflow-contract.json`, `references/tiering.md`, `skills/task-flow/SKILL.md`, and
`.codex/execute-task.md` only for stable defaults omitted by the spec. The spec wins.

## State and phase protocol

`<plugin-root>/scripts/execute-task/runctl.sh` is authoritative for phases, tasks, gates, candidate,
reviews, CI, and DoD. The Markdown journal is human audit narrative only.

At every phase after readiness, first resume state and enter the next phase only when the preceding
one is complete:

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" resume <literal-run-id>
bash "<plugin-root>/scripts/execute-task/runctl.sh" phase <literal-run-id> enter <literal-phase>
```

A fix transition already returns to `implementation/in_progress`; resume it without entering twice.
Pass journal, task, gate, review, and completion evidence through stdin with a quoted heredoc:

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" task <literal-run-id> start <literal-task-id>
bash "<plugin-root>/scripts/execute-task/runctl.sh" task <literal-run-id> complete <literal-task-id> <<'CODEX_TUNER_TASK_EVIDENCE'
<exact diff/check/acceptance evidence>
CODEX_TUNER_TASK_EVIDENCE
bash "<plugin-root>/scripts/execute-task/runctl.sh" gate <literal-run-id> record <dor|testing|acceptance|dod> pass [--sha <candidate-sha>] <<'CODEX_TUNER_GATE_EVIDENCE'
<exact command and result evidence>
CODEX_TUNER_GATE_EVIDENCE
bash "<plugin-root>/scripts/execute-task/runctl.sh" phase <literal-run-id> complete <literal-phase>
bash "<plugin-root>/scripts/execute-task/journal.sh" append <literal-run-id> <<'CODEX_TUNER_EVIDENCE'
<verbatim evidence with literal branch/SHA/PR/check values>
CODEX_TUNER_EVIDENCE
```

Never pass evidence through `eval`, `bash -c`, command substitution, or a double-quoted positional
argument.

Without `--auto`, stop at the end of Phases 1–7 and require separate confirmation before merge.
Phase 0 flows directly into Phase 1 so the execution plan is visible on the initial invocation.

## Phase 0 — readiness

1. Run `scripts/execute-task/prereq-check.sh`.
2. Derive a stable lowercase run ID. Resolve literal branch, target, and `auto_ready`; verify current
   branch ownership, committed spec, unmerged PR state, and clean repository worktree.
3. Validate the full DoR: problem/baseline, architecture/scope, deciding acceptance checks,
   regression test, exact first failing command and expected failure, targeted/full/static/runtime
   commands, environment/data, one-PR delivery, and CI source. A non-code exception needs its reason.
4. Refuse `--auto` unless the spec says `auto_ready: yes`, `ci`, `target_test`, and `full_test` are
   nonblank, and every `[eyes]` item has a replacement or dated waiver.
5. Open and initialize owned state:
   ```bash
   bash "<plugin-root>/scripts/execute-task/preflight.sh" <literal-run-id> <literal-target> --expected-branch <literal-branch>
   bash "<plugin-root>/scripts/execute-task/runctl.sh" init <literal-run-id> --mode <interactive|auto> --spec <repo-relative-spec>
   ```
   `init` opens `readiness/in_progress`; on restart use `resume`.
6. Record `gate ... dor pass` with exact evidence, complete readiness, journal the literal config and
   acceptance, and move the configured card to In Progress after recording its prior status.

Continue directly to Phase 1.

## Phase 1 — visible execution plan

Resume and enter `planning`. Before editing, generating, staging, or delegating task paths, call
`update_plan` with:

- one item for every sequential implementation unit; if independent units will run concurrently,
  one aggregate implementation-batch item in the visible plan and one separate run-state task per unit;
- Testing & Code Verification;
- acceptance evidence;
- candidate finalization/commit;
- owner, Matt, and Claude review;
- PR plus current-SHA CI;
- DoD, merge, and reconciliation.

Keep at most one visible item `in_progress`, as required by `update_plan`; the aggregate batch is that
item while its independent units execute. Add every concrete unit and lifecycle item to run state
with an exact stable ID, phase, owned paths, acceptance slice, and deciding checks over stdin. The
Codex plan is the visible view; run state is the source of truth. On resume, rebuild `update_plan`
from `runctl status` before work continues.

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" task <literal-run-id> add <literal-task-id> <implementation|testing|acceptance|candidate|review|delivery> <<'CODEX_TUNER_TASK'
<owned paths, acceptance slice, dependencies, and deciding checks>
CODEX_TUNER_TASK
```

Complete `planning`, then apply the boundary.

## Phase 2 — implementation

Resume and enter `implementation`; after a fix transition, only resume. This is the only phase where
subagents may mutate product code or tests. Choose effort from `references/tiering.md`.

For behavior changes, write the named regression test first and run the first failing check. Confirm
the expected semantic failure; syntax, config, fixture, or environment failure is not RED. For a
non-code exception, capture the promised alternative baseline.

Parallelize only independent code-writing units:

- one isolated worktree per unit;
- exact non-overlapping paths, acceptance slice, and scoped commands;
- shared contracts, schemas, migrations, generated indexes, and integration files stay parent-owned
  unless one unit owns them exclusively;
- subagents do not change lifecycle state, integrate other units, commit, push, review, merge, or
  delete worktrees.

Subagents may write scoped tests and run scoped checks. The parent reads each complete diff, rejects
scope leakage, independently verifies the unit, and integrates it. Dependent or overlapping units run
sequentially. The parent owns conflicts, authoritative testing, architecture, acceptance, delivery,
and user communication.

Before leaving the mutation phase, reconcile shipped/deferred scope. When the branch completes the
plan, move it with `git mv` to `<plans-root>/ARCHIVE/PLANS/` and run:

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" spec <literal-run-id> relocate <new-repo-relative-spec>
```

Complete state/plan implementation items with diff and scoped-test evidence. File out-of-scope
findings; never absorb them silently. Complete `implementation`, then apply the boundary.

## Phase 3 — Testing & Code Verification

Resume and enter `testing`. Do not write fixes while state says testing.

1. Prove the regression test is green and its negative/mutation check fails when the fix is absent or
   reversed.
2. Run every targeted command and the full regression suite.
3. Run required typecheck, lint, build, generated/migration, and runtime/browser checks.
4. After formatter or `--fix`, read its entire diff and rerun both typecheck and lint.
5. Read full status and diff; account for every file and behavior change.

Establish a claimed pre-existing failure against the task base. If a fix is needed, send the reason to
`phase <run-id> fix`, add the returned implementation item to the visible plan, and repeat from Phase
2. Record `gate ... testing pass` with exact commands/results; it fingerprints the tested worktree.
Complete `testing`, then apply the boundary.

## Phase 4 — acceptance

Resume and enter `acceptance`. Drive each `[machine]` criterion by its named check. For `[eyes]`, drive
the recorded replacement, journal its waiver, or stop in HITL for the exact human step. `--auto`
rejects an item without replacement or waiver.

Record every result. A needed code change goes through `phase fix` and repeats Phases 2–4. Record the
acceptance gate, complete the phase, and apply the boundary.

## Phase 5 — immutable candidate

Resume and enter `candidate`. Do not change the tested tree: candidate recording rejects a tree SHA
that differs from the testing fingerprint. Inspect status and full diff, stage explicit task paths
only, run the artifact guard, inspect the staged diff, and commit conventionally:

```bash
git add -- <path-1> <path-2>
git diff --cached --check
bash "<plugin-root>/scripts/execute-task/guard-artifacts.sh" <literal-run-id>
git diff --cached
git commit -m "<type>: <imperative summary>"
```

Require a clean worktree; record full HEAD through `candidate ... record <sha>` and capture its tree
SHA. Complete `candidate`, then apply the boundary.

## Phase 6 — exact-candidate review

Resume and enter `review`. Read the complete candidate diff and run all three layers against the same
literal base, candidate SHA/tree, and current tracked spec:

1. Perform an owner deep review across every `workflow-contract.json` review lens. All lenses always
   run; small non-sensitive candidates may be serial, while large or sensitive candidates may fan out
   read-only reviewer agents. Do not cap findings.
2. Invoke `$code-review` with the fixed base and committed spec; require its Standards, Spec, and
   architecture/systemic surfaces to have no unresolved blocking finding.
3. Invoke the machine contract with literal `base_sha`, `candidate.sha`, `candidate.tree_sha`, and
   `spec` from `runctl status`:
   ```text
   $codex-cc-triage:claude-review --required --base <literal-base-sha> --spec <current-repo-relative-spec> --thread review-<literal-run-id> --cap 5 Review the complete candidate against the spec using unbiased correctness, architecture, systemic, security/data, and testing/operability lenses.
   ```
   `--cap 5` bounds repair rounds, not findings. Require the exact self-verified
   `CODEX_CC_REQUIRED_REVIEW APPROVE` marker with matching thread, head, tree, base and spec. Pass it
   verbatim as Claude approval evidence; `runctl` rejects missing, duplicated, or mismatched markers.

Validate every finding against candidate source and record it as fixed, refuted with `file:line`, or
explicitly deferred to an issue. Invocation, timeout, partial output, reviewer cap, stale candidate, or
`REQUEST_CHANGES` is not approval. Record `owner-review`, `mattpocock`, and `claude` verdicts with the
exact candidate through stdin.

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" review <literal-run-id> record <owner-review|mattpocock|claude> <APPROVE|REQUEST_CHANGES> <literal-candidate-sha> <<'CODEX_TUNER_REVIEW'
<verbatim verdict, exact required-review marker when applicable, and finding dispositions>
CODEX_TUNER_REVIEW
```

Any code/test change goes through `phase fix`, a new commit, and complete Phases 2–6. It invalidates
testing, acceptance, reviews, CI, and DoD; old approval cannot move forward. Complete `review` only
after every exact-candidate approval exists, then apply the boundary.

## Phase 7 — PR, current-SHA CI, and DoD

Resume and enter `delivery`. Verify clean HEAD equals the reviewed candidate. Push, find or create the
PR with literal base/head/title and a prepared body:

```bash
git push -u origin <literal-branch>
gh pr view <literal-branch> --json number,url,headRefOid,baseRefName || gh pr create --base <literal-target> --head <literal-branch> --title "<literal-title>" --body-file <prepared-body-file>
```

Require candidate = reviewed SHA = pushed SHA = current PR head. Observe required hosted checks on
that SHA; missing, skipped, stale, cancelled, billing-blocked, or red is not green. Record it through
`ci <run-id> record success <candidate-sha> --pr <literal-pr-number>` with exact evidence.

Evaluate every pre-merge DoD item from evidence, record `dod pass --sha <candidate>`, complete delivery,
and require `can-advance` plus `can-merge`. Show PR, SHA, reviews, CI, and DoD. HITL stops for separate
merge confirmation; `--auto` continues only after `can-merge`.

## Phase 8 — merge and reconcile

Resume completed delivery state; rerun the artifact guard and `can-merge`. Recheck open PR, literal
target, exact candidate head, green required CI, acceptance, and review dispositions.

Merge with the spec method automatically only under `--auto`; otherwise require the separate user
confirmation after Phase 7. Confirm actual `MERGED` state, then synchronize issue/board according to
`Closes`/`Fixes` versus partial `Refs`.

Use GitHub's atomic head guard with the recorded PR and candidate:

```bash
gh pr merge <literal-pr-number> --squash --match-head-commit <literal-candidate-sha>
```

Use the spec's literal `--squash` or `--merge` method; never merge a moved head.

While still on the owned branch, append merged/board/cleanup evidence and finish state through stdin:

```bash
bash "<plugin-root>/scripts/execute-task/runctl.sh" finish <literal-run-id> <<'CODEX_TUNER_COMPLETION'
<literal merged PR, issue/board, spec/archive, and cleanup evidence>
CODEX_TUNER_COMPLETION
```

Switch to the literal target, pull `--ff-only`, remove only merged clean worktrees, prune, and delete
proven-merged refs. Do not append to branch-owned state afterward and never hard-code `main`.

## Hard stops

- Incomplete DoR or missing visible plan.
- Missing/false RED, red targeted/full/static/runtime/acceptance check, or unexplained diff.
- Any unresolved `[eyes]` criterion under `--auto`.
- Missing, failed, partial, or stale exact-candidate review, current-SHA CI, or DoD.
- Scope outside the spec, deploy/publish/migration, force-push, bypass flags, broad staging, unsafe
  amend, or commit to target.

Report criteria/evidence, reviewer dispositions, candidate/PR/current-SHA CI equality, DoD, merge,
deferrals, reconciliation, and state path. Never claim CI or merge from an older SHA.
