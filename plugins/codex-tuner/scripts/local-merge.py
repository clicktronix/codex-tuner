#!/usr/bin/env python3
"""Check and fast-forward an authorized local target to a verified candidate."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from delivery_spec import read_spec


def git(*args, cwd=None):
    return subprocess.check_output(['git', *args], cwd=cwd).decode().rstrip('\n')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def merge(args):
    root = Path(git('rev-parse', '--show-toplevel'))
    os.chdir(root)
    head = git('rev-parse', 'HEAD')
    require(args.sha == head and not dirty(), 'expected clean candidate HEAD')
    require(re.fullmatch(r'[0-9a-f]+', args.base) and len(args.base) == len(head), 'expected full base SHA')
    spec = read_spec(head, args.spec)
    require(spec['host'] == 'local' and spec['merge'] == 'ff' and spec['ci'].startswith('none:')
            and spec['ci'][5:].strip(), 'local delivery needs host: local, merge: ff and ci: none:<reason>')
    require(spec['delivery'] in ('merge', 'local'), 'invalid local delivery scope')
    require(spec['delivery'] == 'merge' or args.check_only, 'local merge is reserved')
    require(spec['review'] in ('claude', 'local'), 'unknown review mode')
    git('check-ref-format', '--branch', spec['target'])
    require(spec['target'] != spec['branch'] and git('symbolic-ref', '--short', 'HEAD') == spec['branch'],
            'candidate must be on the task branch')
    target = 'refs/heads/' + spec['target']
    old = git('rev-parse', '--verify', target)
    require(args.base != args.sha, 'review needs a proper comparison base')
    git('merge-base', '--is-ancestor', args.base, args.sha)
    git('merge-base', '--is-ancestor', old, args.sha)
    if spec['review'] == 'claude':
        subprocess.run(['bash', Path(__file__).with_name('check-review.sh'), args.thread,
                        args.sha, args.base, args.spec], check=True)
    notes = git('notes', '--ref=codex-tuner', 'show', args.sha).splitlines()
    verdicts = [line for line in notes if line in (
        f'codex-tuner-verdict: APPROVE {args.sha}', f'codex-tuner-verdict: REQUEST_CHANGES {args.sha}')]
    require(verdicts and verdicts[-1] == f'codex-tuner-verdict: APPROVE {args.sha}', 'missing current APPROVE')
    require(any(line == 'codex-tuner-verified: ' + args.sha and i+1 < len(notes) and notes[i+1].strip()
                and not notes[i+1].startswith('codex-tuner-') for i, line in enumerate(notes)),
            'missing exact-candidate verification')
    prefix = f'codex-tuner-local-ci: {args.sha} '
    require(any(line.startswith(prefix) and line[len(prefix):].strip() for line in notes), 'missing local CI evidence')
    worktree = None
    for entry in git('worktree', 'list', '--porcelain', '-z').split('\0\0'):
        rows = entry.split('\0')
        if 'branch ' + target in rows:
            worktree = rows[0][len('worktree '):]
            break
    if worktree:
        require(not dirty(worktree) and git('symbolic-ref', 'HEAD', cwd=worktree) == target
                and git('rev-parse', 'HEAD', cwd=worktree) == old, 'target worktree changed or is dirty')
    if args.check_only:
        print(f'would fast-forward {target} from {old} to {args.sha}')
        return
    if worktree:
        git('merge', '--ff-only', args.sha, cwd=worktree)
    else:
        git('update-ref', target, args.sha, old)
    require(git('rev-parse', target) == args.sha, 'target moved after merge')
    print(f'{target} now at {args.sha}')


def dirty(cwd=None):
    return git('status', '--porcelain', '-uall', '--ignore-submodules=none', cwd=cwd)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true')
    for name in ('sha', 'thread', 'base', 'spec'):
        parser.add_argument(name)
    try:
        merge(parser.parse_args())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'codex-tuner local merge: {error}')
