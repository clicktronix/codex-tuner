---
name: spec
description: Turn a requested feature, fix or issue into an executable spec, or groom an existing issue for later implementation.
---

# Specify a task

Use the repository's existing approved contract if it still covers the request. For `--groom <issue>`, use [issue grooming](references/groom.md) and finish at the issue. For implementation, hand the spec to [run](../run/SKILL.md) in this session.

## Establish the outcome

Read applicable repository rules, the issue or local task record, affected code, tests and consumers. Follow the repository's tracker instructions and confirm the target branch from Git. Inspect the available delivery route, CI and review capabilities. If a remote is unavailable, use the known local base for discovery and leave publication pending. For versioned dependencies, check primary documentation.

Resolve the desired behaviour, who owns the change, affected boundaries, and what observation will prove each criterion. For stateful changes cover persistence, concurrent updates, identity and recovery where relevant. For visual work use [visual acceptance](../../references/verification.md#visual-acceptance). Name the first failing check or other observable baseline. If a fact can only be learned by running code, make that experiment the first implementation step.

Ask about a material decision only after checking existing evidence. Where available use grilling for unresolved product choices, domain modeling for changed vocabulary, and a read-only second perspective for a risky assumption under the task's existing authority and budget. The author decides which observations change the draft.

## Record the agreement

Use the repository's spec location and spelling. When no convention exists, use `wiki/PLANS/` if it has a wiki, otherwise `docs/PLANS/`. Put the contract and implementation outline in one file. The implementation outline is guidance for Codex's native plan. For coupled repositories, identify the primary spec, record each contribution and its dependency, and specify the evidence for the combined outcome.

```markdown
# <task>
Goal and scope: <observed failure, desired behaviour, boundaries and affected consumers>
Issue: <reference or none>

## Acceptance criteria
- [ ] [machine] <outcome> — <command or interaction and expected observation>
- [ ] [eyes] <judgement> — <human step, machine replacement or dated owner waiver>

## Verification
First failing check or baseline: <command and specific result>
Targeted and full checks: <commands, environment and data>
Implementation outline: <ordered changes with a deciding check for each>

## Delivery
branch: <task branch>
target: <integration branch>
host: github|gitlab|local|pending
delivery: local|draft|pr|merge
merge: squash|merge|ff
review: claude|local
ci: <mode>
tracker: gh|glab|local|none
board: <configured board or none>
auto_ready: yes|no
rollout: <prerequisite and command to confirm it, or none>
```

Choose values from repository policy and the user's authorization. `delivery` records the furthest authorized action. `local` leaves a local handoff. `draft` allows draft publication. `pr` allows an open PR/MR. `merge` requires merge authority and a checked route. Local fast-forward uses `host: local` and `merge: ff`. For unresolved or unsupported destinations use `pending`. Record an explicit local review decision when required external review is waived or the agreed route uses only local review. An unavailable reviewer never changes the contract by itself.

Set `ci` on its own line to one of these modes and put verification commands in the Verification section:

- `required`: the target branch's required checks are the selected ones.
- `any`: the target requires no check, so every check reported on the candidate is selected.
- `none:<reason>`: no hosted check runs; an identified local substitute stands in, recorded with the candidate before merge, and the merge gate refuses it when any check is reported.

Under `required` and `any` a skipped check counts neither way, at least one selected check must pass, and a pending, failed or cancelled check blocks.

A local-only implementation can proceed with unresolved publication, an outstanding human judgement, or a future rollout. Record the item and which step needs it. In coupled work add `second-repo:` for the dependent checkout and spec, and `shared-task:` on the companion.

Set `auto_ready: yes` when the route and checks are known and every human criterion has an observed result, an agreed machine check or an owner waiver. Otherwise use `no` and name the pending decision. Readiness describes the evidence available for unattended delivery. The `delivery` field and the owner's request set its limit.

## Handoff

Present open decisions together. An approved issue or a direct implementation request with settled scope can supply the agreement. A planning-only request ends at the requested draft. When writing the spec, use a task branch if permitted and stage only intended files if commits are authorized. Preserve the working copy for local execution when commits are reserved. Create or update external issues, comments and boards only within the task's publication authority. With `tracker: none`, the spec is the task record.

For an implementation request, start `$codex-tuner:run <spec>` immediately, including from an uncommitted local spec when appropriate. Use `--local-only` to retain local results and `--auto` for requested unattended delivery within the agreed boundary. Native plan tools track the work when available. Goal mode is optional and requires an explicit request to create a goal.
