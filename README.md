# codex-tuner

Codex-native skills for turning a task into a verified pull request without rebuilding Codex's own
task runtime.

## Flow

- `$codex-tuner:spec <issue | description>` reads the repository, resolves material decisions, and
  commits one executable spec. It uses grilling or domain modeling only when the task needs them.
- `$codex-tuner:run [--auto] <spec | task>` uses Codex's native plan and Goal mode, implements and
  tests the task, runs proportionate review, obtains exact-candidate Claude approval, verifies
  required CI, merges through a checked boundary, and cleans up.
- `$codex-tuner:task-flow` supplies branch, PR, tracker, merge, and cleanup conventions.

There is no custom run state, phase machine, journal, or separate plan command. For unattended work,
start `/goal` in Codex and then invoke `$codex-tuner:run --auto ...`. `--auto` grants the task-scoped
delivery actions described by the skill; `/goal` supplies persistence and continuation.

Normal review runs once. A single additional deep owner pass is reserved for sensitive surfaces,
large diffs, cross-service changes, and major architecture boundaries. The authoritative merge gate
is the independent `codex-cc-triage` review bound to the exact candidate, tracked spec, public verdict,
required CI, and PR head.

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
