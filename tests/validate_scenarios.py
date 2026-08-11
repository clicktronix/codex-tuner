#!/usr/bin/env python3
"""Validate execute-task eval scenario structure and reference anchors."""

from __future__ import annotations

import hashlib
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
    contract = json.loads(
        (root / "plugins" / "codex-tuner" / "workflow-contract.json").read_text(
            encoding="utf-8"
        )
    )
    run_skill_sha256 = hashlib.sha256(
        (root / "plugins" / "codex-tuner" / "skills" / "run" / "SKILL.md").read_bytes()
    ).hexdigest()
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
        if port_status.get("contract_version") != contract.get("version"):
            fail(
                f"{scenario_path.name}: codex_port_status must target contract "
                f"{contract.get('version')}"
            )
            failures += 1

        for key in ("expected_behavior", "anti_expectation"):
            value = scenario.get(key)
            if not isinstance(value, list) or not value:
                fail(f"{scenario_path.name}: {key} must be a non-empty array")
                failures += 1

        rendered = json.dumps(scenario, ensure_ascii=False)
        stale_claude_terms = ("TaskCreate", "TaskUpdate", "Claude task list")
        if any(term in rendered for term in stale_claude_terms):
            fail(f"{scenario_path.name}: contains a Claude-only planning primitive")
            failures += 1

        if scenario_path.name == "visible-plan-before-edit.json":
            if "update_plan" not in rendered or "visible Codex plan" not in rendered:
                fail(
                    f"{scenario_path.name}: must probe Codex update_plan semantics"
                )
                failures += 1
            if port_status.get("status") != "live isolated model probe passed" \
                    or "run_model_scenarios.py visible-plan-before-edit" \
                    not in port_status.get("command", "") \
                    or port_status.get("skill_sha256") != run_skill_sha256:
                fail(f"{scenario_path.name}: missing current live-probe evidence")
                failures += 1

        if scenario_path.name == "overlapping-implementation-stays-serial.json":
            query = str(scenario.get("query", "")).lower()
            expected = " ".join(scenario.get("expected_behavior", [])).lower()
            if not all(term in query for term in ("overlap", "depend")) or "serial" not in expected:
                fail(
                    f"{scenario_path.name}: must probe overlapping dependent units "
                    "remaining serial"
                )
                failures += 1
            if port_status.get("status") != "live isolated model probe passed" \
                    or "run_model_scenarios.py overlapping-implementation-stays-serial" \
                    not in port_status.get("command", "") \
                    or port_status.get("skill_sha256") != run_skill_sha256:
                fail(f"{scenario_path.name}: missing current live-probe evidence")
                failures += 1

        if scenario_path.name == "sensitive-small-diff-skip.json":
            expected = " ".join(scenario.get("expected_behavior", [])).lower()
            anti = " ".join(scenario.get("anti_expectation", [])).lower()
            if not all(term in expected for term in ("always runs", "fans out")) \
                    or "does not skip deep review" not in anti:
                fail(
                    f"{scenario_path.name}: must require deep review always and "
                    "risk-based review fan-out"
                )
                failures += 1

        if scenario_path.name == "reviewer-unavailable-fails-closed.json":
            query = str(scenario.get("query", ""))
            expected = " ".join(scenario.get("expected_behavior", [])).lower()
            if "CODEX_CC_REQUIRED_REVIEW APPROVE" not in query \
                    or not all(
                        role in expected
                        for role in ("owner-review", "mattpocock", "claude")
                    ):
                fail(
                    f"{scenario_path.name}: must probe Codex-native owner and "
                    "external Claude approval evidence"
                )
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
