# execute-task

A Codex skill for running repository coding tasks from intake through verified delivery.

`$execute-task` provides acceptance criteria, risk-scaled review, hard verification gates,
resumable local journals, and explicit authority checks before outward-facing actions. It has no
dependency on another agent plugin.

## Install

```bash
codex plugin marketplace add clicktronix/execute-task --ref main
codex plugin add execute-task@execute-task
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

The plugin marketplace lives at `.agents/plugins/marketplace.json`; the plugin is under
`plugins/execute-task/`.

## License

MIT
