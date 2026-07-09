# Eval Scenarios

These decision probes protect the three load-bearing workflow rules: human-only acceptance remains
a hard stop, task-introduced cheap-gate failures are fixed before review, and small sensitive diffs
still receive deep review.

`baseline_observed` and `green_check` preserve the original Claude/Haiku evidence from the source
workflow. `codex_green_check` records a fresh run through the packaged `$execute-task` Codex skill.
The structural validator checks every scenario and its `tests_reference` anchor:

```bash
bash tests/run.sh
```
