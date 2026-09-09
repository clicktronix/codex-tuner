---
name: setup
description: Set up or check repository rule loading for Codex when asked to configure codex-tuner or make project rules discoverable.
---

# Setup

Parse the requested mode: `check` (default, read-only) or `install`. This setup currently owns
repository rule loading, not plugin installation, authentication, boards, or other configuration.
An explicit request to install authorizes this small additive repository change; do not ask again.

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
