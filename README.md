# codex-tuner

A Codex-native collection of reusable engineering workflow skills.

The first packaged skill is `$execute-task`. It runs repository coding tasks from intake through
verified delivery with acceptance criteria, risk-scaled review, hard verification gates, resumable
local journals, and explicit authority checks before outward-facing actions. The collection has no
dependency on another agent plugin.

## Install

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Invoke explicitly:

```text
$execute-task implement issue #123 end to end and open a pull request
```

The skill is explicit-only and will not take over ordinary coding requests automatically.

## Local Development

```bash
bash tests/run.sh
```

The plugin marketplace lives at `.agents/plugins/marketplace.json`; Codex skills are packaged under
`plugins/codex-tuner/skills/`.

## License

MIT
