---
name: task-flow
description: Use for branches, commits, pull requests, GitHub Projects, plans, stacked changes, merge strategy, and cleanup. Apply codex-tuner lifecycle conventions while respecting repository AGENTS.md instructions.
---

# Task Flow

Repository instructions override defaults. Preserve unrelated work and never infer permission for
deploy, publish, migration, force-push, or destructive cleanup.

## Invariants

- Never commit directly to the integration branch.
- Never use `git add -A`, `git add .`, `--no-verify`, `--no-gpg-sign`, or unsafe `--amend`.
- Force-with-lease requires explicit user approval and is forbidden on the integration branch or a
  branch with unresolved review comments.
- Branch: `<type>/<issue>-<kebab-slug>` within 50 characters; without an issue use
  `<type>/<short-slug>` and explain why in the PR.
- Commit: Conventional Commits, one logical change per commit. Mark breaking changes with `!` plus a
  `BREAKING CHANGE:` migration footer.
- For authorized hosted delivery, the task branch and PR/MR attach to the implemented sub-issue, not its parent epic.
- Use `Closes`/`Fixes` only for complete scope and `Refs` for partial or stacked scope.
- PR verification is a link to the checks attached to the candidate under the spec's `ci` mode; do
  not paste long transcripts. A pending or paused check is not absent CI. Modes are defined in
  `../spec/SKILL.md`; under `none:<reason>` the local substitute is recorded on the PR as
  `codex-tuner-local-ci: <sha> <what ran>`.

## Issues, epics, and boards

Follow the spec's tracker and write permissions. Under `tracker: none`, keep the task in its spec.
Use an existing local issue store for `local`, GitLab issues for `glab` and GitHub issues for `gh`.
With tracker writes authorized, use an epic or parent issue for independently reviewed phases.
Update Status and Priority only on a configured, authorized board. Record prior
status before moving it to In Progress. After a confirmed merge, complete the card only for a closing PR;
leave referenced partial work In Progress. With `board: none` issues exist but no project command
runs (`tracker: none` is defined in `../spec/SKILL.md`).

Pass explicit limits to `gh project list`, `field-list`, and `item-list`; their default pagination can
hide cards. Cache stable field and option IDs in repo-local instructions, refresh once after an edit
failure, and treat board failures after merge as reconciliation debt rather than a failed merge.

## Scope of a finding

- **Fix this task's bugs, regressions and missing acceptance criteria**, including missing work they
  depend on. Defect causality and the agreed outcome decide scope, not file location, repository,
  severity, size or finding count. A reviewer's independent improvement is not a new requirement.
- **Tracking a defect does not resolve it.** An unmet acceptance criterion stays open until proved or
  explicitly waived by the user. If access or a user decision blocks it, continue available work and
  report the dependency; do not claim completion. Recording independent future work does not pause
  the run or need a new confirmation, and it is one record for the
  class, not one issue per finding.

## Verification discipline

- After a formatter or autofix, read the diff it produced and re-run the checks that cover what it
  changed; the tool's own zero-error report is not one of them. Choose the checks by the repository
  and the affected criteria.
- Decide whether a finding is pre-existing from defect reachability and the task-base diff, not whether
  its file was already present.
- Review the complete changed surface, including untracked files and consumers of changed contracts.
- For an audit, map the requested scope to examined areas and evidence in its existing report.
  Name unread paths and untested scenarios; completion claims cover only what was examined.

## Plans

Use the repository's spec and archive conventions. Without one, use `wiki/PLANS/` when a wiki exists, otherwise `docs/PLANS/`. Link existing issues when tracker writes are authorized. If the completing PR archives its spec, move it before pinning the review base and spec path. For a local handoff, keep the working spec in place.

## Merge and cleanup

Previews, dedicated MCP servers and test containers follow
[task resources](../../references/resources.md), closing included, also without a merge.

- Feature to integration branch: squash and delete the remote branch unless repo policy says otherwise.
- Stacked PRs: preserve ancestry with merge commits inside the stack; squash only when the stack lands.
- For a GitHub PR verify it reads `MERGED`, then switch to its literal target and `git pull --ff-only`.
- GitLab requires the observed MR state `merged`. For a local fast-forward confirm the literal
  target ref now names the candidate. Remote synchronization applies only to a hosted route.
- Before removing an owned clean worktree or branch, check its tip still equals the delivered
  head. Preserve later commits and unrelated changes. For squash merges use the forge's recorded
  merged head as evidence. Keep draft and handoff branches available to their owner.
- A branch whose PR already merged is finished. Put genuinely new commits on a fresh branch rather than
  rebasing already-squashed history and risking regressions.
