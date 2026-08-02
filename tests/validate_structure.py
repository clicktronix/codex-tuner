#!/usr/bin/env python3
"""Validate the codex-tuner marketplace, release, contract, and skill layout."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path


def load_yaml(text: str) -> object:
    """Parse YAML through Ruby Psych, available on both CI target operating systems."""
    result = subprocess.run(
        [
            "ruby",
            "-rjson",
            "-ryaml",
            "-e",
            (
                "data=YAML.safe_load(STDIN.read, permitted_classes: [], "
                "permitted_symbols: [], aliases: false); print JSON.generate(data)"
            ),
        ],
        input=text,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    plugin = root / "plugins" / "codex-tuner"
    manifest = json.loads((plugin / ".codex-plugin" / "plugin.json").read_text())
    marketplace = json.loads(
        (root / ".agents" / "plugins" / "marketplace.json").read_text()
    )
    contract = json.loads((plugin / "workflow-contract.json").read_text())
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
        try:
            metadata = load_yaml(frontmatter.group(1)) if frontmatter else None
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            metadata = None
        if not isinstance(metadata, dict) or metadata.get("name") != name:
            errors.append(f"{name} frontmatter is invalid")
        elif set(metadata) - {"name", "description", "license", "allowed-tools", "metadata"}:
            errors.append(f"{name} frontmatter has unsupported keys")
        elif not isinstance(metadata.get("description"), str) or not metadata["description"].strip():
            errors.append(f"{name} frontmatter description is invalid")
        elif len(metadata["description"]) > 1024 or any(
            value in metadata["description"] for value in ("<", ">")
        ):
            errors.append(f"{name} frontmatter description is unsafe or too long")
        if not re.fullmatch(r"[a-z0-9-]{1,64}", name) or name.startswith("-") or name.endswith("-"):
            errors.append(f"{name} skill name is invalid")
        if len(skill_text.splitlines()) > 500:
            errors.append(f"{name} exceeds 500 lines")
        agent_text = (skill_dir / "agents" / "openai.yaml").read_text(encoding="utf-8")
        try:
            agent = load_yaml(agent_text)
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            agent = None
        if not isinstance(agent, dict):
            errors.append(f"{name} agents/openai.yaml is invalid YAML")
            continue
        interface = agent.get("interface", {})
        policy = agent.get("policy", {})
        if set(agent) != {"interface", "policy"} or set(interface) != {
            "display_name",
            "short_description",
            "default_prompt",
        } or set(policy) != {"allow_implicit_invocation"}:
            errors.append(f"{name} agents/openai.yaml schema mismatch")
        if not isinstance(interface.get("display_name"), str) or not interface[
            "display_name"
        ].strip():
            errors.append(f"{name} display_name is invalid")
        short_description = interface.get("short_description")
        if not isinstance(short_description, str) or not 25 <= len(short_description) <= 64:
            errors.append(f"{name} short_description must be 25-64 characters")
        if f"$codex-tuner:{name}" not in str(interface.get("default_prompt", "")):
            errors.append(f"{name} default prompt must use the plugin namespace")
        if policy.get("allow_implicit_invocation") is not implicit:
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
        plugin / "references" / "tiering.md",
        plugin / "workflow-contract.json",
    ):
        if not asset.is_file():
            errors.append(f"missing asset: {asset.relative_to(root)}")

    if contract.get("version") != "1.1.0" or len(contract.get("invariants", [])) != 14:
        errors.append("workflow contract mismatch")
    if release_manifest.get(".") != version:
        errors.append("release manifest version mismatch")
    release_config = json.loads((root / "release-please-config.json").read_text())
    if release_config.get("bootstrap-sha") != "6cba092b97756b2aaf6877cf2de6636b05b0e5d0":
        errors.append("release-please bootstrap SHA mismatch")
    if release_config.get("include-component-in-tag") is not False:
        errors.append("release-please tag format is ambiguous")
    if release_config.get("bump-patch-for-minor-pre-major") is not False:
        errors.append("release-please pre-major bump policy mismatch")
    extra_files = release_config.get("packages", {}).get(".", {}).get("extra-files", [])
    if extra_files != [
        {
            "type": "json",
            "path": "plugins/codex-tuner/.codex-plugin/plugin.json",
            "jsonpath": "$.version",
        }
    ]:
        errors.append("release-please plugin version target mismatch")
    if (root / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()[:1] != [
        "# Changelog"
    ]:
        errors.append("CHANGELOG header is invalid")
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
