# Eval scenarios

These decision probes cover the load-bearing readiness, planning, implementation, testing, review,
CI, and acceptance rules in the run lifecycle.

`baseline_observed` and `green_check` preserve historical Claude evidence from the source workflow.
`bash tests/run.sh` validates scenario structure and the model-runner contract with a deterministic
fixture; it does not spend model calls. Run the two acceptance-critical live probes explicitly:

```bash
python3 tests/run_model_scenarios.py
```

The live runner supplies the current `run` skill and self-contained query to an ephemeral, read-only
`codex exec`, requires structured output, and fails unless the visible-plan case calls `update_plan`
before editing and the overlapping/dependent case remains serial under the parent. A structural pass
is not behavioral evidence; record `codex_port_status` as passed only after this command succeeds.
