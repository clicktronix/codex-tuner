#!/usr/bin/env python3
"""Resolve the fetch and push project of the authorized Git remote."""
import os
import re
import subprocess
import sys
from urllib.parse import urlsplit


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def config(key):
    result = subprocess.run(['git', 'config', '--get', key], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise ValueError(f'cannot read Git setting {key}')
    return result.stdout.strip()


def project(url):
    if '://' in url:
        parsed = urlsplit(url)
        host, path = parsed.hostname, parsed.path.lstrip('/')
        if parsed.scheme not in ('ssh', 'https', 'http', 'git') or not host or parsed.query or parsed.fragment:
            raise ValueError('remote does not identify a forge project')
        if parsed.port and parsed.scheme in ('http', 'https'):
            host = f'{host}:{parsed.port}'
    else:
        remote = re.fullmatch(r'(?:[^@/:]+@)?([\w.-]+):(.+)', url)
        if not remote:
            raise ValueError('delivery needs a forge remote')
        host, path = remote.groups()
    if path.endswith('.git'):
        path = path[:-4]
    parts = path.rstrip('/').split('/')
    if len(parts) < 2 or any(not re.fullmatch(r'[\w.-]+', p) or p in ('.', '..') for p in parts):
        raise ValueError('invalid forge project path')
    return host.lower(), '/'.join(parts)


def destination():
    remotes = git('remote').splitlines()
    branch = subprocess.run(['git', 'symbolic-ref', '--quiet', '--short', 'HEAD'],
                            capture_output=True, text=True).stdout.strip()
    name = (os.environ.get('CODEX_TUNER_REMOTE') or (branch and config(f'branch.{branch}.pushRemote')) or
            config('remote.pushDefault') or (branch and config(f'branch.{branch}.remote')) or
            (remotes[0] if len(remotes) == 1 else ''))
    if name not in remotes or name.startswith('-') or any(c.isspace() for c in name):
        raise ValueError('select the task remote with CODEX_TUNER_REMOTE')
    fetch = project(git('remote', 'get-url', name))
    pushes = git('remote', 'get-url', '--push', '--all', name).splitlines()
    if len(pushes) != 1 or project(pushes[0]) != fetch:
        raise ValueError('fetch and push must select one forge project')
    return name, *fetch


if __name__ == '__main__':
    try:
        print(*destination(), sep='\t')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'codex-tuner destination: {error}')
