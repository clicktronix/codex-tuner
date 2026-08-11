# Run defaults

Optional stable repository defaults for `$codex-tuner:run`. Save a customized copy as
`.codex/execute-task.md`. A committed spec wins where both provide a value.

- **target_test**: focused regression command for the changed behavior.
- **full_test**: full regression command.
- **static/build checks**: stable typecheck, lint, build, generated-artifact, or migration commands.
- **ci**: GitHub required checks and how to observe them; at least one must be configured on the
  target branch.
- **merge**: `squash` or `merge`, plus the default target branch.
- **tracker**: `gh` or `none`.
- **board**: project title and owner, or `none`.

Task-specific first-failure proof, branch, target, scope, acceptance criteria, waivers, and
`auto_ready` belong in the spec. This file never grants unattended or outward-facing authority.
