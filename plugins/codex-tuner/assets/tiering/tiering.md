# Effort tiering and sensitive surfaces

`$codex-tuner:run` reads this file for implementation dispatch and review depth. This is the single
source of the sensitive-surface list.

Choose the higher tier when uncertain:

| Tier | Effort | Qualifies when |
| --- | --- | --- |
| mechanical | `low` | The complete solution is already specified: moves, renames, generated updates, codemods, or scaffolding copied from a named sibling. |
| standard | `medium` | Ordinary feature or fix inside one module with established conventions and unit-level acceptance. |
| hard | `high` | Design freedom remains: new abstractions, concurrency, cross-cutting contracts, or data-model changes. |
| sensitive | `xhigh`, never delegated blind | Any sensitive surface below. The owning agent reads the complete diff regardless of who typed it. |

## Sensitive surfaces

- authentication, authorization, secrets, cryptography;
- migrations and destructive data operations;
- public APIs, persisted schemas, and cross-service contracts;
- money, payments, pricing, billing, and entitlements;
- infrastructure, CI, deployment, and release configuration;
- security-relevant input handling such as injection, SSRF, path traversal, unsafe deserialization, and
  server-side allowlists.

Diff size is not a risk measure. If sensitivity cannot be ruled out, treat the change as sensitive.

## Delegated-unit contract

Before accepting a unit, the dispatching agent must read its complete diff, run the scoped cheap gate,
and check the acceptance criteria stated at dispatch. On failure, redispatch once at the same tier with
concrete `file:line` feedback; after a second failure, escalate one tier. Parallel file edits require
isolated worktrees.

Decomposition, acceptance judgement, review of delegated output, merge/deploy decisions, and user-facing
communication are never tiered down.
