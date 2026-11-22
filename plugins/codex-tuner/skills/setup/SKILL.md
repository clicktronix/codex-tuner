---
name: setup
description: Check Codex repository instructions, rule discovery and delivery prerequisites, or install the repository's rule-loading block when requested.
---

# Setup

Default to a read-only check. Report each requested capability and which step needs any missing dependency. Local discovery and verification can proceed while an external route is unavailable.

**Instructions.** Read the effective root `AGENTS.override.md` or `AGENTS.md`, nested rules and their referenced sources. When asked to audit or reorganize instructions, identify contradictory rules with their scopes, keep the canonical copy and show the proposed changes. Preserve manual policy. Ask the owner to settle a contradiction only when its sources and the request leave a real choice.

**Rule loading.** Run `python3 ../../scripts/agent-rules-setup.py check --repo <checkout>`, resolving the script relative to this skill directory. For an authorized installation use `install`, inspect the diff and rerun `check`. Exit 0 means installed or current, 1 means check found a missing or misplaced block, and 2 means conflict or operational failure. A nonempty root override takes precedence. Read applicable rule bodies through [agent-rules](../agent-rules/SKILL.md). Codex reads updated startup instructions on a fresh session.

**Delivery readiness.** When preparing a run, inspect local Git and the selected target, the repository's CI and tracker policy, then the CLI and login for the selected host. For external Claude review, inspect `codex plugin list --json --marketplace codex-cc-triage`, the enabled plugin's skill entry and `claude --version`. A required review uses the companion's actual capabilities. For an older installation, preserve its pinned cap and state. Report any upgrade or authentication needed for that step. Keep this check free of model calls and external writes.

**Task resources.** Check trusted lifecycle hooks only if the workflow needs a managed preview or service. Otherwise use the repository's existing foreground teardown. See [task resources](../../references/resources.md).
