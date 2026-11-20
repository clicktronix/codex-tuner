---
name: deep-review
description: Review a high-risk or cross-boundary change against its complete candidate, callers, data invariants, and verification evidence, including a standalone audit request.
---

# Deep Review

Identify the comparison base and candidate SHA, the spec or requested outcome, and the verification record. For a working-tree audit also include staged, unstaged and untracked changes and label the result with its actual scope. A required approval needs a clean candidate.

For a committed candidate, resolve both refs to literal SHAs and capture the inventory from the repository root:

```bash
git --literal-pathspecs diff --name-status -z --find-renames --ignore-submodules=none "$base...$candidate" > "$scratch/changed.z"
git --literal-pathspecs diff --no-ext-diff --no-textconv --find-renames --ignore-submodules=none --submodule=short "$base...$candidate" > "$scratch/candidate.diff"
```

For a worktree audit, also inspect both staged and unstaged diffs and read the untracked files from `git ls-files --others --exclude-standard -z`. For a large change, group the inventory by affected boundary. Give each reviewer or sequential pass its paths, candidate and expected evidence. Include both endpoints of renames and inspect submodule, binary and generated changes with the corresponding repository tools. Reconcile the union of examined paths with the inventory, recording any omission before reporting coverage.

1. Trace the complete diff to affected consumers and persistent data. Include repository-specific rules and changes to public behaviour.
2. Inspect correctness, ownership boundaries, data handling, failure recovery and verification. For a large independent area, use an authorized read-only reviewer when the host supports delegation. The owning agent reconciles overlapping findings and covers unassigned paths.
3. For each finding identify the triggering condition, user-visible effect, location and evidence. Test the scenario where feasible. Check whether the suite would distinguish the faulty behaviour.
4. Return confirmed findings, refuted hypotheses that materially affected the review, and specific coverage gaps. For a review request, report findings. For an authorized fix, record the verdict on the reviewed revision before editing, then verify the new candidate. An external approval, waiver or publication follows the owner's delivery contract.
