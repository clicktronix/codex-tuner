#!/usr/bin/env python3
"""Run isolated Codex behavior probes for the two acceptance-critical scenarios."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


PROBES = {
    "visible-plan-before-edit": {
        "decision": "publish_plan_before_edit",
        "first_action": "update_plan",
        "parallelism": ("not_applicable", "serial"),
        "owner": "parent",
    },
    "overlapping-implementation-stays-serial": {
        "decision": "serial",
        "first_action": ("update_plan", "integrate_shared_contract"),
        "parallelism": "serial",
        "owner": "parent",
    },
}

OUTPUT_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": ["decision", "first_action", "parallelism", "owner", "rationale"],
    "properties": {
        "decision": {
            "enum": ["publish_plan_before_edit", "edit_without_plan", "serial", "parallel"]
        },
        "first_action": {
            "enum": ["update_plan", "edit", "write_prose", "integrate_shared_contract", "delegate_both"]
        },
        "parallelism": {"enum": ["not_applicable", "serial", "parallel"]},
        "owner": {"enum": ["parent", "subagents"]},
        "rationale": {"type": "string", "minLength": 1},
    },
}


def output_schema_for(name: str) -> dict[str, object]:
    schema = json.loads(json.dumps(OUTPUT_SCHEMA))
    properties = schema["properties"]
    if name == "visible-plan-before-edit":
        properties["decision"]["enum"] = ["publish_plan_before_edit", "edit_without_plan"]
        properties["first_action"]["enum"] = ["update_plan", "edit", "write_prose"]
        properties["parallelism"]["enum"] = ["not_applicable", "serial"]
    else:
        properties["decision"]["enum"] = ["serial", "parallel"]
        properties["first_action"]["enum"] = [
            "update_plan",
            "integrate_shared_contract",
            "delegate_both",
        ]
        properties["parallelism"]["enum"] = ["serial", "parallel"]
    return schema


def fail(message: str) -> int:
    print(f"FAIL {message}", file=sys.stderr)
    return 1


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    selected = sys.argv[1:] or list(PROBES)
    unknown = [name for name in selected if name not in PROBES]
    if unknown:
        return fail(f"unknown model scenario(s): {', '.join(unknown)}")

    skill = (root / "plugins" / "codex-tuner" / "skills" / "run" / "SKILL.md").read_text(
        encoding="utf-8"
    )
    codex_bin = os.environ.get("CODEX_EVAL_BIN", "codex")
    model = os.environ.get("CODEX_EVAL_MODEL")
    failures = 0

    with tempfile.TemporaryDirectory(prefix="codex-tuner-model-eval-") as temp:
        temp_path = Path(temp)
        for name in selected:
            schema_path = temp_path / f"{name}.schema.json"
            schema_path.write_text(json.dumps(output_schema_for(name)), encoding="utf-8")
            scenario = json.loads(
                (root / "tests" / "scenarios" / f"{name}.json").read_text(encoding="utf-8")
            )
            output_path = temp_path / f"{name}.json"
            prompt = (
                "Apply the supplied run skill to the self-contained scenario. Do not read files, "
                "call tools, or infer missing facts. Choose the safe next action and return only "
                "the required JSON object.\n\n"
                f"<run_skill>\n{skill}\n</run_skill>\n\n"
                f"<scenario>\n{scenario['query']}\n</scenario>\n"
            )
            command = [
                codex_bin,
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--skip-git-repo-check",
                "--sandbox",
                "read-only",
                "--output-schema",
                str(schema_path),
                "--output-last-message",
                str(output_path),
                "-C",
                str(temp_path),
            ]
            if model:
                command.extend(["--model", model])
            command.append("-")
            try:
                completed = subprocess.run(
                    command,
                    input=prompt,
                    text=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    timeout=int(os.environ.get("CODEX_EVAL_TIMEOUT", "300")),
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"FAIL {name}: {error}", file=sys.stderr)
                failures += 1
                continue
            if completed.returncode != 0:
                print(
                    f"FAIL {name}: codex exec exited {completed.returncode}: "
                    f"{completed.stderr.strip()}",
                    file=sys.stderr,
                )
                failures += 1
                continue
            try:
                answer = json.loads(output_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                print(f"FAIL {name}: invalid result: {error}", file=sys.stderr)
                failures += 1
                continue
            expected = PROBES[name]
            mismatches = {}
            for key, value in expected.items():
                allowed = value if isinstance(value, tuple) else (value,)
                if answer.get(key) not in allowed:
                    mismatches[key] = {"expected": list(allowed), "actual": answer.get(key)}
            if mismatches:
                print(f"FAIL {name}: {json.dumps(mismatches, sort_keys=True)}", file=sys.stderr)
                failures += 1
            else:
                print(f"PASS model-scenario {name}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
