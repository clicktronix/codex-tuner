#!/usr/bin/env python3
"""Publish a completed review round from its saved receipt, or keep it local."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from destination import destination
from delivery_spec import read_spec


def pull_head(api, endpoint, project, branch, target):
    pull = json.loads(subprocess.check_output([*api, endpoint]))
    head = pull.get("head") or {}
    base = pull.get("base") or {}
    if pull.get("state") != "open":
        raise ValueError("PR is no longer open")
    for side in (head, base):
        name = (side.get("repo") or {}).get("full_name") or ""
        if name.casefold() != project.casefold():
            raise ValueError("PR repository differs from the selected delivery project")
    if head.get("ref") != branch or base.get("ref") != target:
        raise ValueError("PR source or target differs from the reviewed spec")
    return head["sha"]


def finish(receipt, pr, spec):
    # The orchestrator retains this file and its basename across handoffs and retries.
    with receipt.open(encoding="utf-8") as record:
        fcntl.flock(record, fcntl.LOCK_EX)
        line = record.read()
        if line.endswith("\n"):
            line = line[:-1]
        object_format = subprocess.check_output(['git', 'rev-parse', '--show-object-format'], text=True).strip()
        oid = {'sha1': '[0-9a-f]{40}', 'sha256': '[0-9a-f]{64}'}.get(object_format)
        if not oid:
            raise ValueError('unknown Git object format')
        checked = re.fullmatch(
            rf"CODEX_CC_REQUIRED_REVIEW (APPROVE) thread=\S+ head=({oid}) "
            rf"tree={oid} fingerprint=[0-9a-f]{{64}} base_sha={oid} spec_path=(.+)", line
        )
        decision = checked or re.fullmatch(
            rf"codex-tuner-verdict: (APPROVE|REQUEST_CHANGES) ({oid})", line
        )
        if not decision:
            raise ValueError("expected one completed verdict with its full reviewed SHA")
        verdict, sha = decision.group(1, 2)
        if checked:
            if spec and spec != checked[3]:
                raise ValueError('spec path differs from the checked receipt')
            spec = checked[3]
        marker = f"codex-tuner-verdict: {verdict} {sha}"
        if pr is None:
            print(f"{marker}\nLocal receipt: {receipt}")
            return

        if not spec:
            raise ValueError('supply --spec for a public verdict without a companion marker')
        contract = read_spec(sha, spec)
        if contract.get('host', 'github') != 'github' or contract.get('delivery') == 'local':
            raise ValueError('spec reserves GitHub publication')
        if verdict == 'APPROVE' and not checked and contract.get('review', 'claude') != 'local':
            raise ValueError('public external approval requires the companion marker')
        _, host, project = destination()
        api = [os.environ.get("CODEX_TUNER_GH", "gh"), "api", "--hostname", host]
        endpoint = f"repos/{project}/pulls/{pr}"

        round_id = hashlib.sha256(receipt.name.encode()).hexdigest()
        tag = f"<!-- codex-tuner-round: {round_id} -->"
        body = f"{marker}\n\n{tag}"
        author = json.loads(subprocess.check_output([*api, "user"]))["id"]
        pages = json.loads(subprocess.check_output([*api, "--paginate", "--slurp", endpoint + "/reviews"]))
        for page in pages:
            for review in page:
                if (review.get("user") or {}).get("id") != author:
                    continue
                if tag not in (review["body"] or "").splitlines():
                    continue
                if (review["body"] != body or review["commit_id"] != sha
                        or review["state"] != "COMMENTED"):
                    raise ValueError("existing round disagrees with receipt; inspect the published review")
                print(review["html_url"])
                return

        branch = contract.get('branch')
        if not branch:
            raise ValueError('the reviewed spec must name the task branch before publication')
        current_head = pull_head(api, endpoint, project, branch, contract['target'])
        if current_head != sha:
            # A lost response can leave a historical verdict pending after a normal push.
            commits = json.loads(subprocess.check_output([*api, "--paginate", "--slurp", endpoint + "/commits"]))
            if not any(commit["sha"] == sha for page in commits for commit in page):
                raise ValueError(f"reviewed commit {sha} is not in PR {pr}; retained {receipt}")
            if pull_head(api, endpoint, project, branch, contract['target']) != current_head:
                raise ValueError('PR changed while checking its commits; retry the saved receipt')
        subprocess.run([*api, endpoint + "/reviews", "--method", "POST", "-f", "event=COMMENT",
                        "-f", f"commit_id={sha}", "-f", f"body={body}", "--jq", ".html_url"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="one uniquely named file per review round")
    parser.add_argument("--pr", type=int, help="authorized GitHub PR number in the delivery repository")
    parser.add_argument("--spec", help="tracked spec path at the judged commit")
    args = parser.parse_args()
    if args.pr is not None and args.pr < 1:
        parser.error("--pr requires a positive PR number")
    try:
        finish(args.receipt, args.pr, args.spec)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"codex-tuner review: {error}")
