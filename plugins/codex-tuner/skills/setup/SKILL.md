---
name: setup
description: Set up or check repository rule loading for Codex when asked to configure codex-tuner or make project rules discoverable.
---

# Setup

Parse the requested mode: `check` (default, read-only) or `install`. This setup owns the
repository's instruction health and rule loading for Codex. It does not own plugin installation,
authentication, boards, statuslines or Claude-only settings: those are Claude Code host concerns
and stay with `/cc-tuner:setup`. An explicit request to install authorizes the small **additive**
repository change below; do not ask again for it.

Run as nodes, each detect → propose → apply → verify, and report one row per node at the end.
A node that fails blocks only what depends on it; the rest still run and still report.

**Node 1 — instruction cleanup.** Read the repository's `AGENTS.md`, `CLAUDE.md` and
`.claude/rules/*.md` and its stated policy. Healthy instructions are left alone. When they
contradict each other or bury an always-on rule under procedure, propose the rebuilt files as a full
diff. This rewrites canonical instructions, so the additive rule above does not cover it: ask for
confirmation only when the request did not already authorise a reorganisation, or when the diff
settles a contradiction by choosing one side. A declined diff leaves every file untouched; node 2
still runs. In `check` mode, report what would change and write nothing.

**Node 2 — rule loading.** The additive block, below.

Locate `scripts/agent-rules-setup.py` relative to this skill's installed plugin directory
(`../../scripts/agent-rules-setup.py` from this directory), not a guessed cache version or shell CWD.
Run it with Python 3, the chosen mode, and `--repo` pointing at the intended repository/worktree.
The helper resolves Git root from that location; it needs no network or extra Python packages.

Show the proposed diff and outcome. Exit 0 means installed/current. Exit 1 means a change is
needed in check mode: `MISSING` adds the block; `PRESENT BUT NOT FIRST` moves it to the start.
Install reports `INSTALLED` or `MOVED` accordingly. Exit 2 means a conflict or operational failure. A non-empty root `AGENTS.override.md` takes
precedence; otherwise setup adds the block to `AGENTS.md`. Empty overrides stay empty so they
do not hide the owner's instructions. Existing prose, rules, skills, and docs are preserved.
A conflicting block or symlink is reported without overwrite: inspect the owner's file and resolve
within the user's authorized scope rather than adding a second competing copy.

Then use `agent-rules` to read the applicable rule bodies and linked contracts for the actual task.
Report missing references discovered there. Setup status only proves the loading instruction is
present; it does not prove rule/index completeness or that a model will follow it.

The plugin supplies the skill once; do not generate per-repository skill copies or a second rule
index. The installed instruction also works when the plugin is absent. No hooks, user settings,
CLAUDE.md imports, rule moves, commits, or network actions are performed by the helper. Claude Code
continues using its native rule loader. Recommend a fresh Codex session for changed startup context;
do not claim installation injected new instructions into an already-running session.

**Report.** End with one table — `node | before | action | verification` — both rows always
present, including skipped or blocked ones. The owner's own re-read of the files it just wrote is
not an independent audit and is not labelled as one; this setup requires no second provider.
