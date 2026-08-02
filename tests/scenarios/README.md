# Eval scenarios

These decision probes cover the three load-bearing run rules: bare `[eyes]` criteria stop, red cheap
gates are fixed before review, and small sensitive diffs still receive deep review.

`baseline_observed` and `green_check` preserve historical Claude evidence from the source workflow.
`codex_port_status` is deliberately not a pass: the 0.3 spec/run port needs fresh isolated Codex probes
before new behavioral evidence can be claimed. `bash tests/run.sh` validates scenario structure and
anchors only; it does not execute a model evaluation.
