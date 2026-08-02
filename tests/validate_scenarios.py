#!/usr/bin/env python3
"""Validate execute-task eval scenario structure and reference anchors."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REQUIRED_KEYS = {
    "skills",
    "tests_reference",
    "query",
    "baseline_failure",
    "expected_behavior",
    "anti_expectation",
}


def github_anchor(heading: str) -> str:
    normalized = heading.strip().lower()
    normalized = re.sub(r"[^\w\- ]", "", normalized)
    return normalized.replace(" ", "-")


def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    failures = 0

    for scenario_path in sorted((root / "tests" / "scenarios").glob("*.json")):
        try:
            scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            fail(f"{scenario_path.name}: {error}")
            failures += 1
            continue

        missing = REQUIRED_KEYS - scenario.keys()
        if missing:
            fail(f"{scenario_path.name}: missing keys {sorted(missing)}")
            failures += 1

        if scenario.get("skills") != ["run"]:
            fail(f"{scenario_path.name}: skills must be ['run']")
            failures += 1

        port_status = scenario.get("codex_port_status", {})
        if port_status.get("plugin_version") != "0.3.0":
            fail(f"{scenario_path.name}: codex_port_status must target plugin 0.3.0")
            failures += 1

        for key in ("expected_behavior", "anti_expectation"):
            value = scenario.get(key)
            if not isinstance(value, list) or not value:
                fail(f"{scenario_path.name}: {key} must be a non-empty array")
                failures += 1

        reference = scenario.get("tests_reference", "")
        if "#" not in reference:
            fail(f"{scenario_path.name}: tests_reference needs a heading anchor")
            failures += 1
            continue

        relative_path, anchor = reference.split("#", 1)
        target = root / relative_path
        if not target.is_file():
            fail(f"{scenario_path.name}: missing reference file {relative_path}")
            failures += 1
            continue

        headings = {
            github_anchor(match.group(1))
            for line in target.read_text(encoding="utf-8").splitlines()
            if (match := re.match(r"^#{1,6}\s+(.+)$", line))
        }
        if anchor not in headings:
            fail(f"{scenario_path.name}: missing anchor #{anchor} in {relative_path}")
            failures += 1

    if failures:
        return 1

    print("PASS scenarios")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
