---
name: task-flow
description: Use when Codex creates or reviews task branches, commits, pull requests, GitHub Projects cards, implementation plans, stacked changes, merge strategy, or post-merge cleanup. Apply the same one-task lifecycle used by codex-tuner spec/run while respecting repository-specific AGENTS.md instructions.
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
- One task branch and PR attach to the implemented sub-issue, not its parent epic.
- Use `Closes`/`Fixes` only for complete scope and `Refs` for partial or stacked scope.
- PR verification links to hosted CI; do not paste long transcripts.

## Issues, epics, and boards

Use an epic with native sub-issues when work spans repositories, PRs, or independently reviewed phases.
Otherwise use one issue. Add the issue to the configured board with Status and Priority. Record prior
status before moving it to In Progress. After a confirmed merge, complete the card only for a closing PR;
leave referenced partial work In Progress. File each deferred review finding as its own issue.

Pass explicit limits to `gh project list`, `field-list`, and `item-list`; their default pagination can
hide cards. Cache stable field and option IDs in repo-local instructions, refresh once after an edit
failure, and treat board failures after merge as reconciliation debt rather than a failed merge.

## Verification discipline

- Show a regression test failing against the pre-fix behavior or an equivalent negative mutation.
- After formatter or autofix, read its diff and run both typecheck and lint.
- Decide whether a finding is pre-existing from defect reachability and the task-base diff, not whether
  its file was already present.
- Review the complete changed surface, including untracked files and consumers of changed contracts.

## Plans

Store durable specs in `wiki/PLANS/` when a wiki exists, otherwise `docs/PLANS/`. Link issue and spec in
both directions. Move a completed spec to the matching `ARCHIVE/PLANS/` in the PR that completes it;
never create a standalone archival PR.

## Merge and cleanup

- Feature to integration branch: squash and delete the remote branch unless repo policy says otherwise.
- Stacked PRs: preserve ancestry with merge commits inside the stack; squash only when the stack lands.
- Verify the PR reads `MERGED`, then switch to its literal target and `git pull --ff-only`.
- Inspect worktrees before removal. Remove only a clean worktree whose branch is proven merged, prune
  stale registrations, delete merged local branches with `-d`, and fetch with prune.
- A branch whose PR already merged is finished. Put genuinely new commits on a fresh branch rather than
  rebasing already-squashed history and risking regressions.
