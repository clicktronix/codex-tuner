# codex-tuner

Codex-native skills for the same development lifecycle used by `cc-tuner`, adapted to Codex tools and
instruction surfaces.

## Development flow

- `$codex-tuner:spec <issue | description>` reads the repository, resolves requirements, creates the
  task branch, and commits a machine-checkable spec with explicit `auto_ready` state.
- `$codex-tuner:run [--auto] <spec>` publishes a visible plan before mutation, permits parallel agents
  only for independent code-writing units, then enforces Testing & Code Verification, acceptance, an
  immutable candidate, three exact-SHA reviews, PR/current-SHA CI, DoD, merge, and reconciliation.
  Without `--auto` it stops at each declared boundary. `--auto` never authorizes deploy, publish, or
  migration.
- `$codex-tuner:task-flow` supplies branch, commit, PR, board, plan, merge, and cleanup conventions.

The harness-neutral invariants are versioned in
`plugins/codex-tuner/workflow-contract.json`. Claude-specific statusline, memory-file, and Stop-hook
features remain outside this repository; semantic workflow parity does not require copying
harness-only surfaces.

Authoritative run state and journals live under `.agent-state/codex-tuner/`; the published schema is
`plugins/codex-tuner/schemas/run-state.schema.json`. The self-ignored directory avoids protected
`.git/` writes and works in Codex's default workspace sandbox. The artifact guard also covers the
legacy `.codex/execute-task-runs/` path.

The delivery gate verifies Claude approval against the state held by the single enabled
`codex-cc-triage@codex-cc-triage` installation; pasted approval text is not authority. GitHub delivery
also requires at least one required check on the target branch. Codex instructions and optional hooks
are guardrails; candidate/tree, reviewer-state, CI, and merge-head checks are the runtime boundaries.

## Install

Install the three runtime companion skills from the current
[Matt Pocock repository](https://github.com/mattpocock/skills) globally for Codex:

```bash
npx skills@latest add mattpocock/skills --global --agent codex --skill grilling domain-modeling code-review --yes
```

Install or update the independent Claude Code reviewer; its Phase 6 required-review contract needs an
installed and authenticated `claude` executable and emits approval only for the unchanged candidate:

```bash
codex plugin marketplace add clicktronix/codex-cc-triage --ref main
codex plugin add codex-cc-triage@codex-cc-triage
```

Then install `codex-tuner`:

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Start a new Codex thread after installation so Codex discovers the new skills. `spec` and `run` are
explicit-only; `task-flow` can load when branch/PR lifecycle work matches its description. Run
`/skills` to browse installed skills, or invoke `$grilling`, `$domain-modeling`, and `$code-review`
directly. `codex-tuner` passes the committed spec and tracker config directly, so Matt Pocock's
repository bootstrap skill is not a runtime dependency.

Optional stable repository defaults can be scaffolded with:

```bash
bash <plugin-root>/scripts/execute-task/config-init.sh \
  <plugin-root>/assets/execute-task/config.template.md
```

## Development

```bash
bash tests/run.sh
```

CI runs the same suite on Ubuntu and macOS. Structure validation also enforces the current
[OpenAI plugin submission contract](https://developers.openai.com/plugins/deploy/submission-errors).
Releases are maintained by release-please; do not hand-edit version fields independently.

## License

MIT
