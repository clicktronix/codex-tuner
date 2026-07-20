---
name: execute-task
description: Use when the user asks Codex to execute a coding task, issue, ticket, or implementation plan end to end, from intake and planning through implementation, verification, review, CI, and an explicitly authorized delivery step.
---

# Execute Task

Drive one repository-scoped coding task to a verified stopping point. Keep momentum through routine
decisions. Pause only for a real hard stop: unresolved product intent, conflicting user changes,
failed required verification, human-only acceptance, or an outward-facing action the user has not
authorized.

## Start

1. Read the nearest `AGENTS.md`, repository docs, and relevant local instructions.
2. Inspect the current branch, worktree status, recent commits, and task source. Preserve unrelated
   user changes; a dirty tree is context, not an automatic refusal.
3. If `.codex/execute-task.md` exists, read it as repo-specific constraints. It can narrow delivery
   capability but never grants authority for an outward-facing action. Otherwise infer commands and
   conventions from the repository. Ask only when an unresolved choice would materially change the
   result.
4. Determine delivery authority from the request. Local edits and verification are in scope.
   Commit, push, PR, merge, deploy, publish, and migration actions require explicit authority from
   the request or a later user instruction.
5. Choose a unique run id beginning with an ASCII letter or digit and containing only letters,
   digits, dot, underscore, and hyphen. Resolve `<skill-dir>` to the directory containing this
   `SKILL.md`. Start the local-only journal and pass `--require-clean` when the repository constraint
   requires it:

   ```bash
   bash "<skill-dir>/scripts/preflight.sh" <run-id> [target-ref] [--require-clean]
   ```

6. Track the workflow with the environment's plan/task mechanism. Append important decisions and
   verification results with:

   ```bash
   bash "<skill-dir>/scripts/journal.sh" append <run-id> "<result>"
   ```

## 1. Intake And Acceptance

- Resolve an issue or ticket reference through the available tracker tooling.
- Restate the intended outcome, constraints, non-goals, and definition of done.
- Classify each acceptance criterion as `[machine]` or `[eyes]`.
- Treat an `[eyes]` criterion as human-only only when judgment cannot be reduced to an observable
  check. Do not relabel it merely to avoid a checkpoint.
- If the task is already precise, proceed without manufacturing a brainstorm gate.

## 2. Research And Plan

- Inspect the exact code paths, consumers, tests, and architecture boundaries before editing.
- For libraries, frameworks, APIs, CLIs, or cloud services, fetch current primary documentation
  using the documentation tool required by the repository. Do not send proprietary ticket text to
  external search services.
- Build a concrete plan with verification attached to each risky step.
- Stress-test assumptions yourself. When independent agents are available, use one for a blind plan
  review on high-risk or cross-module work; validate every objection against the code before acting.
- Do not require an external reviewer or a magic `APPROVE` token to proceed.

## 3. Implement

- Implement in dependency order and keep changes traceable to the task.
- Add focused tests before or with behavior changes. Scale coverage with risk and blast radius.
- Use independent agents only for genuinely separable work. Avoid concurrent edits to the same
  files unless the environment provides isolated worktrees.
- Preserve existing conventions and unrelated worktree changes.
- Keep the user informed during long work and journal decisions that matter for resumption.

## 4. Cheap Gate

Run the repository's fastest meaningful checks before expensive review: focused tests, typecheck,
lint, or a targeted build. Prefer commands from `AGENTS.md`, package scripts, or
`.codex/execute-task.md`.

- Fix failures introduced by the task before continuing.
- Distinguish pre-existing failures with evidence; do not silently claim the gate passed.
- Re-run the smallest check that proves the fix, then broaden when the touched surface warrants it.

## 5. Acceptance

- Exercise the real behavior against every acceptance criterion, not only unit tests.
- Drive `[machine]` UI criteria through the available browser tooling and inspect console/runtime
  failures. Verify backend criteria through API or behavior-level checks.
- For an unmet `[eyes]` criterion, provide the evidence and stop for the user's judgment unless the
  user explicitly waives that criterion.
- Record what was verified and what remains unverified.

## 6. Risk-Scaled Review

Review the complete changed surface, including untracked files and consumers of changed contracts.
Validate findings against live code before applying them, and fix every instance of an accepted bug
class within scope.

Always perform a deep review when the diff touches any of these surfaces:

- authentication, authorization, secrets, or cryptography;
- migrations, destructive data operations, or irreversible state changes;
- public APIs, persisted schemas, or cross-service contracts;
- money, payments, pricing, billing, or entitlements;
- infrastructure, CI, deployment, or release configuration;
- injection, SSRF, path traversal, unsafe deserialization, or similar trust boundaries.

For a diff of at most 50 changed lines across at most 5 files that is confidently non-sensitive,
one thorough self-review is sufficient. Otherwise use an independent reviewer when available, or
perform a second pass with explicit correctness, security, regression, and test lenses. Uncertainty
about sensitivity means deep review.

After review fixes, re-run every check or acceptance path the fixes could have affected.

## 7. Reconcile And CI

- Reconcile the implementation with the plan and acceptance criteria.
- Mark shipped, changed, and deliberately deferred scope explicitly.
- Run the repository's required full local checks. A task-introduced required check that remains red
  is a hard stop. When hosted CI requires a pushed ref, defer CI observation until the authorized
  push/PR step; never claim it ran before then.
- Re-check the final diff for accidental files, secrets, generated caches, and local artifacts.

## 8. Deliver

Before any authorized commit, push, PR, merge, deploy, publish, or migration:

1. Run the artifact guard with the current run id. It uses the immutable target SHA captured by
   preflight rather than a moving branch name:

   ```bash
   bash "<skill-dir>/scripts/guard-artifacts.sh" <run-id>
   ```

2. Show or inspect the exact diff and untracked files. Stage paths intentionally; never use
   `git add -A` as a shortcut.
3. State the side effect and rollback path for deploys, publishes, migrations, and merges.
4. Confirm the action is already authorized. If it is not, stop and ask.
5. Perform the action, verify the resulting remote and hosted CI state, and journal the outcome.

## Hard Stops

Stop and involve the user when:

- product intent or acceptance criteria remain materially ambiguous;
- proceeding would overwrite or entangle unrelated user changes;
- a required check fails because of the task and cannot be repaired safely;
- an `[eyes]` criterion remains unverified without an explicit waiver;
- a security or data-integrity decision cannot be resolved from code and policy;
- an outward-facing or irreversible action lacks explicit authority.

Autonomy never means guessing. Conversely, do not stop for routine implementation choices that can
be resolved from code, repository instructions, or current documentation.

## Resume

Run journals live under `.agent-state/codex-tuner/execute-task-runs/` and are ignored by the state
directory's own `.gitignore`. To resume, read the journal and metadata, compare their branch/base
SHA with the current repository, inspect new changes since the last entry, and continue from the
first unverified step. Never trust an old green result after relevant code or dependencies changed.
