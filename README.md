# codex-tuner

Codex-native skills for turning a task into a verified pull request without rebuilding Codex's own
task runtime.

## Flow

- `$codex-tuner:spec <issue | description>` reads the repository, resolves material decisions, and
  commits one executable spec. It uses grilling or domain modeling only when the task needs them.
- `$codex-tuner:run [--auto] <spec | task>` commits a short contract first when given a task, then
  uses Codex's native plan and Goal mode to implement, test, review, merge through a checked boundary,
  and clean up.
- `$codex-tuner:task-flow` supplies branch, PR, tracker, merge, and cleanup conventions.

There is no custom run state, phase machine, journal, or separate plan command. For unattended work,
start `/goal` in Codex and then invoke `$codex-tuner:run --auto ...`. `--auto` grants the task-scoped
delivery actions described by the skill; `/goal` supplies persistence and continuation.

Normal review runs once. A single additional deep owner pass is reserved for sensitive surfaces,
large diffs, cross-service changes, and major architecture boundaries. The authoritative merge gate
is the independent `codex-cc-triage` review bound to the exact candidate, tracked spec, public verdict,
required CI, and PR head.

## Repository rules

[Research and design](docs/2026-09-09-agent-rules-research.md).

`agent-rules` loads the target repository's applicable instructions, modular rules, and linked
contracts before a review or change, including when a task crosses into another repository.
The plugin supplies one generic skill; project rules stay in their existing canonical files.

Run `$codex-tuner:setup install` to add a short loading instruction to the repository's root
`AGENTS.md` (or the effective `AGENTS.override.md`). Use `check` instead of `install` for a
read-only status and diff. Repeated installation is a no-op. Conflicting managed blocks and
symlinks require inspection and are not overwritten. No rule index or per-repo skill is copied.
The instruction remains usable without the plugin; it is guidance, not an enforcement hook.

## Install

Install the companion reviewer:

```bash
codex plugin marketplace add clicktronix/codex-cc-triage --ref main
codex plugin add codex-cc-triage@codex-cc-triage
```

Install the review and optional discovery skills:

```bash
npx skills@latest add mattpocock/skills --global --agent codex \
  --skill grilling domain-modeling code-review --yes
```

Install codex-tuner:

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Start a new Codex session so the skills are discovered.

## Development

```bash
bash tests/run.sh
```

CI runs the same suite on Ubuntu and macOS. PR titles use Conventional Commit subjects because squash
merges feed release-please.

## License

MIT
