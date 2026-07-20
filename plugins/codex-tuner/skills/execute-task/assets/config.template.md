# Execute Task Overrides

Optional repository-specific constraints for `$codex-tuner:execute-task`. Save a customized copy as
`.codex/execute-task.md`. Omit fields that Codex can infer from `AGENTS.md` and repository scripts.

- **target_branch**: integration branch, such as `main`.
- **branch**: feature-branch naming and clean-tree policy.
- **cheap_gate**: focused tests, typecheck, lint, or targeted build.
- **test**: full behavior or smoke verification.
- **ci**: CI command or check source.
- **delivery**: maximum permitted surface: `none`, `commit`, `push`, `pr`, or `merge`. This never
  authorizes an action; authority must come from the user's request or later instruction.
- **merge**: merge method and target branch. This does not grant delivery authority by itself.
- **tracker**: `gh`, `glab`, or `none`.
- **allow_unverified_manual**: whether an explicitly waived `[eyes]` criterion may remain open.
- **require_clean**: set `true` only when this repository forbids starting from a dirty tree.
