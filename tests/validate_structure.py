#!/usr/bin/env python3
"""Validate the codex-tuner marketplace, plugin, and skill layout."""

from __future__ import annotations

import json
import re
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    plugin = root / "plugins" / "codex-tuner"
    manifest = json.loads((plugin / ".codex-plugin" / "plugin.json").read_text())
    marketplace = json.loads(
        (root / ".agents" / "plugins" / "marketplace.json").read_text()
    )
    errors: list[str] = []

    if manifest.get("name") != "codex-tuner" or manifest.get("version") != "0.2.0":
        errors.append("plugin name/version mismatch")
    entry = marketplace.get("plugins", [{}])[0]
    if entry.get("name") != "codex-tuner":
        errors.append("marketplace plugin name mismatch")
    if entry.get("source", {}).get("path") != "./plugins/codex-tuner":
        errors.append("marketplace source path mismatch")

    skill_dir = plugin / "skills" / "execute-task"
    skill_text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", skill_text, re.DOTALL)
    if match is None or "name: execute-task" not in match.group(1):
        errors.append("execute-task frontmatter is invalid")
    agent_text = (skill_dir / "agents" / "openai.yaml").read_text(encoding="utf-8")
    if "$codex-tuner:execute-task" not in agent_text:
        errors.append("default prompt must use the plugin namespace")
    for script in ("preflight.sh", "journal.sh", "guard-artifacts.sh", "lib.sh"):
        if not (skill_dir / "scripts" / script).is_file():
            errors.append(f"missing script: {script}")

    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 1
    print("PASS structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
