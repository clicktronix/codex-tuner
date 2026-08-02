# codex-tuner

Codex-native skills for the same development lifecycle used by `cc-tuner`, adapted to Codex tools and
instruction surfaces.

## Development flow

- `$codex-tuner:spec <issue | description>` reads the repository, resolves requirements, creates the
  task branch, and commits a machine-checkable spec with explicit `auto_ready` state.
- `$codex-tuner:run [--auto] <spec>` continues that branch through implementation, acceptance, review,
  intentional staging, PR, current-SHA CI, merge, and cleanup. Without `--auto` it stops at each phase
  boundary. `--auto` never authorizes deploy, publish, or migration.
- `$codex-tuner:task-flow` supplies branch, commit, PR, board, plan, merge, and cleanup conventions.

The harness-neutral invariants are versioned in
`plugins/codex-tuner/workflow-contract.json`. Claude-specific statusline, memory-file, and Stop-hook
features remain outside this repository; semantic workflow parity does not require copying
harness-only surfaces.

Runtime journals live under `.agent-state/codex-tuner/`. The self-ignored directory avoids protected
`.git/` writes and works in Codex's default workspace sandbox. The artifact guard also covers the legacy
`.codex/execute-task-runs/` path.

## Install

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Start a new Codex thread after installation. `spec` and `run` are explicit-only; `task-flow` can load
when branch/PR lifecycle work matches its description.

Optional stable repository defaults can be scaffolded with:

```bash
bash <plugin-root>/scripts/execute-task/config-init.sh \
  <plugin-root>/assets/execute-task/config.template.md
```

## Development

```bash
bash tests/run.sh
```

CI runs the same suite on Ubuntu and macOS. Releases are maintained by release-please; do not hand-edit
version fields independently.

## License

MIT
