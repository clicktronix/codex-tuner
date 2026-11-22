# codex-tuner

Codex skills for planning, implementing and verifying a change through its authorized delivery point.

## Flow

- `$codex-tuner:spec <issue | description>` prepares an executable spec. `--groom <issue>` records decisions for later. An implementation request continues into `run` once the scope is settled.
- `$codex-tuner:run [--local-only | --auto] <spec | task>` uses the native plan, verifies the result and follows the agreed local, draft, PR/MR or merge boundary.
- `$codex-tuner:verify-feature` verifies the requested behaviour. `$codex-tuner:deep-review` audits a candidate and its affected consumers. Both also work as standalone requests.
- `$codex-tuner:task-flow` supplies branch, PR, tracker, merge, and cleanup conventions.

Every skill, `run` included, allows implicit invocation: Codex may select these skills when the task calls for them; `--auto` and merge still need the user's request. For unattended work the user may also start a native goal. The delivery scope and repository permissions apply in either mode.

Review depth follows the risk of the change. The [run skill](plugins/codex-tuner/skills/run/SKILL.md) describes review evidence and the checked delivery routes.

[Acceptance evidence](plugins/codex-tuner/references/verification.md) maps the spec's criteria to
observed results and remaining gaps, including visual comparison when the task needs it.

## Repository rules

Background for maintainers changing agent-rules: [research and design](docs/2026-09-09-agent-rules-research.md).

`agent-rules` loads the target repository's applicable instructions, modular rules, and linked
contracts before a review or change, including when a task crosses into another repository.
The plugin supplies one generic skill; project rules stay in their existing canonical files.

Run `$codex-tuner:setup install` to add a short loading instruction to the repository's root
`AGENTS.md` (or the effective `AGENTS.override.md`). Use `check` instead of `install` for a
read-only status and diff. Repeated installation is a no-op. Conflicting managed blocks and
symlinks require inspection and are not overwritten. No rule index or per-repo skill is copied.
The block goes before existing prose to fit Codex's budget cutoff. See
`plugins/codex-tuner/skills/setup/SKILL.md` for details. The instruction works without the plugin;
it is guidance, not an enforcement hook.

## Install

For workflows that use Claude review, install the companion reviewer, version 0.8.0 or newer:

```bash
codex plugin marketplace add clicktronix/codex-cc-triage --ref main
codex plugin add codex-cc-triage@codex-cc-triage
```

To use the optional review and discovery skills:

```bash
npx skills@latest add mattpocock/skills --global --agent codex \
  --skill grilling domain-modeling code-review --yes
```

Install codex-tuner:

```bash
codex plugin marketplace add clicktronix/codex-tuner --ref main
codex plugin add codex-tuner@codex-tuner
```

Start a new Codex session so the skills are discovered. Review and trust the plugin's lifecycle
hooks through `/hooks`; enabling a plugin does not trust its hooks automatically.

## Resource lifecycle

[Task resources](plugins/codex-tuner/references/resources.md) covers task-owned previews, dedicated
MCP servers and disposable containers. Heavy checks run through the same `heavy.sh` as cc-tuner and
share its machine-wide queue.

## Development

```bash
bash tests/run.sh
```

CI runs the same suite on Ubuntu and macOS. With Codex CLI and a companion checkout, run `bash tests/companion-integration.sh ../codex-cc-triage` to exercise the producing reviewer and consuming merge gate together. It uses an isolated registry, a local Git repository and the companion's offline Claude fixture.

PR titles use Conventional Commit subjects because squash merges feed release-please.

## License

MIT
