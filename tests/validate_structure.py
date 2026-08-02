#!/usr/bin/env python3
"""Validate the codex-tuner marketplace, release, contract, and skill layout."""

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
    contract = json.loads((root / "workflow-contract.json").read_text())
    release_manifest = json.loads((root / ".release-please-manifest.json").read_text())
    errors: list[str] = []

    version = manifest.get("version")
    if manifest.get("name") != "codex-tuner" or not re.fullmatch(
        r"\d+\.\d+\.\d+", str(version)
    ):
        errors.append("plugin name/version is invalid")
    entry = marketplace.get("plugins", [{}])[0]
    if entry.get("name") != "codex-tuner":
        errors.append("marketplace plugin name mismatch")
    if entry.get("source", {}).get("path") != "./plugins/codex-tuner":
        errors.append("marketplace source path mismatch")

    expected_skills = {"spec": False, "run": False, "task-flow": True}
    actual_skills = {path.parent.name for path in (plugin / "skills").glob("*/SKILL.md")}
    if actual_skills != set(expected_skills):
        errors.append(
            f"skill set mismatch: got {sorted(actual_skills)}, expected {sorted(expected_skills)}"
        )
    for name, implicit in expected_skills.items():
        skill_dir = plugin / "skills" / name
        skill_text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
        frontmatter = re.match(r"^---\n(.*?)\n---\n", skill_text, re.DOTALL)
        if frontmatter is None or f"name: {name}" not in frontmatter.group(1):
            errors.append(f"{name} frontmatter is invalid")
        if len(skill_text.splitlines()) > 500:
            errors.append(f"{name} exceeds 500 lines")
        agent_text = (skill_dir / "agents" / "openai.yaml").read_text(encoding="utf-8")
        if f"$codex-tuner:{name}" not in agent_text:
            errors.append(f"{name} default prompt must use the plugin namespace")
        expected_policy = f"allow_implicit_invocation: {str(implicit).lower()}"
        if expected_policy not in agent_text:
            errors.append(f"{name} invocation policy mismatch")

    scripts = plugin / "scripts" / "execute-task"
    for script in (
        "config-init.sh",
        "guard-artifacts.sh",
        "journal.sh",
        "lib.sh",
        "preflight.sh",
    ):
        if not (scripts / script).is_file():
            errors.append(f"missing script: {script}")
    for asset in (
        plugin / "assets" / "execute-task" / "config.template.md",
        plugin / "assets" / "tiering" / "tiering.md",
    ):
        if not asset.is_file():
            errors.append(f"missing asset: {asset.relative_to(root)}")

    if contract.get("version") != "1.0.0" or len(contract.get("invariants", [])) != 14:
        errors.append("workflow contract mismatch")
    if release_manifest.get(".") != version:
        errors.append("release manifest version mismatch")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"## [{version}]" not in changelog:
        errors.append("CHANGELOG has no current version section")
    if list(root.rglob("SKILL.md")) and any(
        "[TODO:" in path.read_text(encoding="utf-8")
        for path in root.rglob("SKILL.md")
    ):
        errors.append("skill TODO placeholder found")

    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 1
    print("PASS structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
