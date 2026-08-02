# Run defaults

Optional stable repository defaults for `$codex-tuner:run`. Save a customized copy as
`.codex/execute-task.md`. A committed spec wins where both provide a value.

- **cheap_gate**: fast type/lint/unit command.
- **test**: full regression or behavior-level command.
- **ci**: required hosted checks and how to observe them.
- **merge**: `squash` or `merge`, plus the default target branch.
- **tracker**: `gh`, `glab`, or `none`.
- **board**: project title and owner, or `none`.
- **effort_tiering**: `on` or `off` (default `on`).
- **small_diff_budget**: default ≤50 changed lines and ≤5 files; sensitive changes never qualify.

Task-specific branch, target, scope, acceptance criteria, waivers, and `auto_ready` belong in the spec.
This file never grants unattended or outward-facing authority.
