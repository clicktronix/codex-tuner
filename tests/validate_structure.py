#!/usr/bin/env python3
"""Validate the codex-tuner marketplace, release, contract, and skill layout.

Public listing constraints mirror https://developers.openai.com/plugins/deploy/submission-errors.
"""

from __future__ import annotations

import json
import math
import re
import subprocess
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse


SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
SKILL_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
CATEGORIES = {
    "Productivity",
    "Creativity",
    "Developer Tools",
    "Business & Operations",
    "Data & Analytics",
    "Communication",
    "Education & Research",
    "Security",
    "Finance",
    "Healthcare",
    "Travel",
    "Entertainment",
    "Other",
}


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


def valid_text(value: object, limit: int, *, one_line: bool = True) -> bool:
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        return False
    for character in value:
        if character in {"\u2028", "\u2029"}:
            return False
        if unicodedata.category(character) in {"Cc", "Cf"} and not (
            character == "\n" and not one_line
        ):
            return False
    return not one_line or "\n" not in value


def valid_https_url(value: object) -> bool:
    if not valid_text(value, 1024) or any(character.isspace() for character in value):
        return False
    parsed = urlparse(value)
    return (
        parsed.scheme == "https"
        and bool(parsed.hostname)
        and parsed.username is None
        and parsed.password is None
    )


def relative_luminance(color: str) -> float:
    channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    first_luminance = relative_luminance(first)
    second_luminance = relative_luminance(second)
    lighter = max(first_luminance, second_luminance)
    darker = min(first_luminance, second_luminance)
    return (lighter + 0.05) / (darker + 0.05)


def svg_dimensions(path: Path) -> tuple[float, float] | None:
    try:
        root = ET.fromstring(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ET.ParseError):
        return None
    if root.tag.rsplit("}", 1)[-1] != "svg":
        return None
    view_box = root.get("viewBox")
    if view_box is not None:
        values = re.split(r"[\s,]+", view_box.strip())
        if len(values) != 4 or any(
            NUMBER_RE.fullmatch(value) is None for value in values
        ):
            return None
        width, height = float(values[2]), float(values[3])
    else:
        raw_width, raw_height = root.get("width"), root.get("height")
        if (
            raw_width is None
            or raw_height is None
            or NUMBER_RE.fullmatch(raw_width) is None
            or NUMBER_RE.fullmatch(raw_height) is None
        ):
            return None
        width, height = float(raw_width), float(raw_height)
    if not all(math.isfinite(value) and value > 0 for value in (width, height)):
        return None
    return width, height


def validate_brand_asset(
    plugin: Path,
    interface: dict[str, object],
    field: str,
    errors: list[str],
) -> None:
    raw_path = interface.get(field)
    if not isinstance(raw_path, str) or not raw_path.startswith("./assets/"):
        errors.append(f"interface.{field} must start with ./assets/")
        return
    relative = PurePosixPath(raw_path)
    if (
        relative.is_absolute()
        or ".." in relative.parts
        or "\\" in raw_path
        or raw_path != f"./{relative.as_posix()}"
    ):
        errors.append(f"interface.{field} is unsafe")
        return
    path = plugin.joinpath(*relative.parts)
    resolved = path.resolve()
    if (
        not resolved.is_relative_to(plugin.resolve())
        or any(
            plugin.joinpath(*relative.parts[:index]).is_symlink()
            for index in range(1, len(relative.parts) + 1)
        )
        or not path.is_file()
    ):
        errors.append(f"interface.{field} must reference a regular file")
        return
    if path.stat().st_size > 5 * 1024 * 1024:
        errors.append(f"interface.{field} exceeds 5 MiB")
    if path.suffix.lower() != ".svg":
        errors.append(f"interface.{field} must use a square SVG in this plugin")
        return
    dimensions = svg_dimensions(path)
    if dimensions is None:
        errors.append(f"interface.{field} SVG is invalid or has no numeric dimensions")
        return
    width, height = dimensions
    if width != height or not 48 <= width <= 4096:
        errors.append(f"interface.{field} must be square and 48-4096 pixels")


def validate_manifest(
    plugin: Path, manifest: dict[str, object], errors: list[str]
) -> str:
    name = manifest.get("name")
    if not isinstance(name, str) or NAME_RE.fullmatch(name) is None:
        errors.append("plugin name is invalid")
        name = ""
    elif name != "codex-tuner":
        errors.append("plugin name must be codex-tuner")
    version = manifest.get("version")
    if (
        not isinstance(version, str)
        or len(version) > 64
        or SEMVER_RE.fullmatch(version) is None
    ):
        errors.append("plugin version is invalid")
    if not valid_text(manifest.get("description"), 1024, one_line=False):
        errors.append("plugin description is invalid")
    author = manifest.get("author")
    if not isinstance(author, dict) or not valid_text(author.get("name"), 120):
        errors.append("plugin author.name is invalid")
    for field in ("homepage", "repository"):
        if field in manifest and not valid_https_url(manifest[field]):
            errors.append(f"plugin {field} must be an HTTPS URL")
    if manifest.get("skills") != "./skills/" or not (plugin / "skills").is_dir():
        errors.append("plugin skills path mismatch")
    for excluded in ("apps", "mcpServers"):
        if excluded in manifest:
            errors.append(f"skills-only plugin must not declare {excluded}")

    interface = manifest.get("interface")
    if not isinstance(interface, dict):
        errors.append("plugin interface is invalid")
        return name
    text_fields = {
        "displayName": (30, True),
        "shortDescription": (30, True),
        "longDescription": (4000, False),
        "developerName": (80, True),
    }
    for field, (limit, one_line) in text_fields.items():
        if not valid_text(interface.get(field), limit, one_line=one_line):
            errors.append(f"interface.{field} is invalid or exceeds {limit} characters")
    if interface.get("category") not in CATEGORIES:
        errors.append("interface.category is unsupported")

    capabilities = interface.get("capabilities")
    if not isinstance(capabilities, list) or len(capabilities) > 20:
        errors.append("interface.capabilities must contain at most 20 strings")
    elif any(not valid_text(value, 120) for value in capabilities):
        errors.append("interface.capabilities contains an invalid entry")

    prompts = interface.get("defaultPrompt")
    if isinstance(prompts, str):
        prompts = [prompts]
    if not isinstance(prompts, list) or not prompts or len(prompts) > 3:
        errors.append("interface.defaultPrompt must contain one to three prompts")
    else:
        normalized: set[str] = set()
        for prompt in prompts:
            if not valid_text(prompt, 128) or "@" in str(prompt):
                errors.append("interface.defaultPrompt contains an invalid prompt")
                continue
            key = unicodedata.normalize("NFKC", " ".join(prompt.split())).casefold()
            if key in normalized:
                errors.append("interface.defaultPrompt contains duplicate prompts")
            normalized.add(key)

    if not valid_https_url(interface.get("websiteURL")):
        errors.append("interface.websiteURL must be an HTTPS URL")
    for field in ("supportURL", "privacyPolicyURL", "termsOfServiceURL"):
        if field in interface and not valid_https_url(interface[field]):
            errors.append(f"interface.{field} must be an HTTPS URL")
    if "screenshots" in interface:
        errors.append("skills-only plugin must not declare screenshots")
    color = interface.get("brandColor")
    if not isinstance(color, str) or HEX_COLOR_RE.fullmatch(color) is None:
        errors.append("interface.brandColor must use #RRGGBB")
    elif contrast_ratio(color, "#FFFFFF") < 2:
        errors.append("interface.brandColor must have 2:1 contrast against white")
    dark_color = interface.get("brandColorDark")
    if dark_color is not None and (
        not isinstance(dark_color, str) or HEX_COLOR_RE.fullmatch(dark_color) is None
    ):
        errors.append("interface.brandColorDark must use #RRGGBB")
    elif isinstance(dark_color, str) and contrast_ratio(dark_color, "#212121") < 2:
        errors.append("interface.brandColorDark must have 2:1 contrast against #212121")
    for field in ("composerIcon", "logo"):
        validate_brand_asset(plugin, interface, field, errors)
    if "logoDark" in interface:
        validate_brand_asset(plugin, interface, "logoDark", errors)
    if isinstance(author, dict) and author.get("name") != interface.get(
        "developerName"
    ):
        errors.append("author.name and interface.developerName must match")
    return name


def validate_agent_metadata(
    skill_dir: Path,
    name: str,
    implicit: bool,
    errors: list[str],
) -> None:
    agent_path = skill_dir / "agents" / "openai.yaml"
    try:
        agent = load_yaml(agent_path.read_text(encoding="utf-8"))
    except (
        OSError,
        UnicodeDecodeError,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ):
        agent = None
    if not isinstance(agent, dict):
        errors.append(f"{name} agents/openai.yaml is invalid YAML")
        return
    if set(agent) - {"interface", "policy", "dependencies"}:
        errors.append(f"{name} agents/openai.yaml has unsupported top-level keys")

    interface = agent.get("interface")
    allowed_interface = {
        "display_name",
        "short_description",
        "icon_small",
        "icon_large",
        "brand_color",
        "default_prompt",
    }
    if not isinstance(interface, dict) or set(interface) - allowed_interface:
        errors.append(f"{name} agents/openai.yaml interface is invalid")
        interface = {}
    if not valid_text(interface.get("display_name"), 64):
        errors.append(f"{name} display_name is invalid")
    short_description = interface.get("short_description")
    if not valid_text(short_description, 64) or len(short_description) < 25:
        errors.append(f"{name} short_description must be 25-64 characters")
    prompt = interface.get("default_prompt")
    if not valid_text(prompt, 1024) or f"$codex-tuner:{name}" not in str(prompt):
        errors.append(f"{name} default prompt must use the plugin namespace")
    brand_color = interface.get("brand_color")
    if brand_color is not None and (
        not isinstance(brand_color, str) or HEX_COLOR_RE.fullmatch(brand_color) is None
    ):
        errors.append(f"{name} brand_color must use #RRGGBB")
    for field in ("icon_small", "icon_large"):
        raw_path = interface.get(field)
        if raw_path is None:
            continue
        if not isinstance(raw_path, str) or not raw_path.strip():
            errors.append(f"{name} {field} must be a non-empty relative path")
            continue
        relative = PurePosixPath(raw_path)
        path = skill_dir.joinpath(*relative.parts)
        resolved = path.resolve()
        if (
            relative.is_absolute()
            or ".." in relative.parts
            or "\\" in raw_path
            or not resolved.is_relative_to(skill_dir.resolve())
            or any(
                skill_dir.joinpath(*relative.parts[:index]).is_symlink()
                for index in range(1, len(relative.parts) + 1)
            )
            or not path.is_file()
        ):
            errors.append(
                f"{name} {field} must reference a regular file inside the skill"
            )

    policy = agent.get("policy")
    if not isinstance(policy, dict) or set(policy) - {
        "products",
        "allow_implicit_invocation",
    }:
        errors.append(f"{name} agents/openai.yaml policy is invalid")
        policy = {}
    if policy.get("products") != ["CODEX"]:
        errors.append(f"{name} must be scoped to the CODEX product")
    if policy.get("allow_implicit_invocation") is not implicit:
        errors.append(f"{name} invocation policy mismatch")

    dependencies = agent.get("dependencies")
    if dependencies is not None:
        if not isinstance(dependencies, dict) or set(dependencies) - {"tools"}:
            errors.append(f"{name} agents/openai.yaml dependencies are invalid")
        elif not isinstance(dependencies.get("tools"), list) or any(
            not isinstance(tool, dict) for tool in dependencies["tools"]
        ):
            errors.append(f"{name} dependencies.tools must be a list of mappings")


def validate(root: Path) -> list[str]:
    plugin = root / "plugins" / "codex-tuner"
    manifest = json.loads((plugin / ".codex-plugin" / "plugin.json").read_text())
    marketplace = json.loads(
        (root / ".agents" / "plugins" / "marketplace.json").read_text()
    )
    contract = json.loads((plugin / "workflow-contract.json").read_text())
    release_manifest = json.loads((root / ".release-please-manifest.json").read_text())
    errors: list[str] = []

    plugin_name = validate_manifest(plugin, manifest, errors)
    version = manifest.get("version")
    entries = marketplace.get("plugins", [])
    if not isinstance(entries, list) or len(entries) != 1:
        errors.append("marketplace must contain exactly one plugin")
        entry: dict[str, object] = {}
    else:
        entry = entries[0] if isinstance(entries[0], dict) else {}
    if entry.get("name") != "codex-tuner":
        errors.append("marketplace plugin name mismatch")
    source = entry.get("source")
    if (
        not isinstance(source, dict)
        or source.get("source") != "local"
        or source.get("path") != "./plugins/codex-tuner"
    ):
        errors.append("marketplace source path mismatch")
    if entry.get("policy") != {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL",
    }:
        errors.append("marketplace policy mismatch")
    manifest_interface = manifest.get("interface")
    manifest_category = (
        manifest_interface.get("category")
        if isinstance(manifest_interface, dict)
        else None
    )
    if entry.get("category") != manifest_category:
        errors.append("marketplace category mismatch")

    expected_skills = {"spec": False, "run": False, "task-flow": True}
    actual_skills = {
        path.name
        for path in (plugin / "skills").iterdir()
        if path.is_dir() and not path.name.startswith(".")
    }
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
        elif set(metadata) != {"name", "description"}:
            errors.append(f"{name} frontmatter must contain only name and description")
        elif not valid_text(metadata.get("description"), 1024, one_line=False) or any(
            value in metadata["description"] for value in ("<", ">")
        ):
            errors.append(f"{name} frontmatter description is unsafe or invalid")
        if SKILL_NAME_RE.fullmatch(name) is None or len(name) > 64:
            errors.append(f"{name} skill name is invalid")
        if len(f"{plugin_name}:{name}") > 64:
            errors.append(
                f"{name} combined plugin and skill identity exceeds 64 characters"
            )
        if len(skill_text.splitlines()) > 500:
            errors.append(f"{name} exceeds 500 lines")
        if frontmatter and not skill_text[frontmatter.end() :].strip():
            errors.append(f"{name} skill body is empty")
        validate_agent_metadata(skill_dir, name, implicit, errors)

    scripts = plugin / "scripts" / "execute-task"
    for script in (
        "config-init.sh",
        "guard-artifacts.sh",
        "journal.sh",
        "lib.sh",
        "prereq-check.sh",
        "preflight.sh",
    ):
        script_path = scripts / script
        if not script_path.is_file():
            errors.append(f"missing script: {script}")
        elif script_path.stat().st_mode & 0o111 == 0:
            errors.append(f"script is not executable: {script}")
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
    if (
        release_config.get("bootstrap-sha")
        != "6cba092b97756b2aaf6877cf2de6636b05b0e5d0"
    ):
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
    if any(
        "[TODO:" in path.read_text(encoding="utf-8") for path in root.rglob("SKILL.md")
    ):
        errors.append("skill TODO placeholder found")
    return errors


def main() -> int:
    root = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) == 2
        else Path(__file__).resolve().parent.parent
    )
    errors = validate(root)
    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 1
    print("PASS structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
