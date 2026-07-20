# codex-tuner

A Codex-native collection of reusable engineering workflow skills.

The first packaged skill is `$codex-tuner:execute-task`. It runs repository coding tasks from intake
through verified delivery with acceptance criteria, risk-scaled review, hard verification gates,
resumable local journals, and explicit authority checks before outward-facing actions. The
collection has no dependency on another agent plugin.

## Install

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Invoke explicitly:

```text
$codex-tuner:execute-task implement issue #123 end to end and open a pull request
```

The skill is explicit-only and will not take over ordinary coding requests automatically.

Runtime journals live under `.agent-state/codex-tuner/`. The directory is self-ignored, so the
scripts do not modify protected `.git/` metadata and work in Codex's default `workspace-write`
sandbox. Version 0.2 replaces the older `.codex/execute-task-runs/` location; existing files there
are left untouched and remain covered by the delivery artifact guard.

## Local Development

```bash
bash tests/run.sh
```

The plugin marketplace lives at `.agents/plugins/marketplace.json`; Codex skills are packaged under
`plugins/codex-tuner/skills/`.

## License

MIT
