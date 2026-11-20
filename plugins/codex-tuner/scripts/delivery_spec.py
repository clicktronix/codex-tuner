"""Read delivery fields from the exact commit named by a run or review receipt."""
import json
from pathlib import PurePosixPath
import re
import subprocess
import sys


def read_spec(sha, name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or any(ord(c) < 32 or ord(c) == 127 for c in name):
        raise ValueError('invalid repository-relative spec path')
    root = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).rstrip('\n')
    entry = subprocess.check_output(['git', '-C', root, '--literal-pathspecs', 'ls-tree', '-z', sha, '--', name])
    mode = entry.partition(b' ')[0]
    if mode not in (b'100644', b'100755'):
        raise ValueError(f'spec must be a tracked regular file at {sha}: {name}')
    content = subprocess.check_output(['git', '-C', root, 'show', f'{sha}:{name}'], text=True)
    lines = content.splitlines()
    headings = [i for i, line in enumerate(lines) if line.rstrip() == '## Delivery']
    if len(headings) > 1:
        raise ValueError('duplicate Delivery section')
    if headings:
        start = headings[0] + 1
        end = next((i for i in range(start, len(lines)) if lines[i].startswith('## ')), len(lines))
        lines = lines[start:end]
    fields = {}
    for line in lines:
        match = re.match(r'^(branch|target|merge|ci|host|delivery|review):\s*(.*)$', line)
        if match:
            key, value = match.groups()
            # Older spec templates append a description after the mode.
            value = value.partition(' — ')[0].strip()
            if key in fields or not value:
                raise ValueError(f'duplicate or empty spec field {key}')
            fields[key] = value
    if not fields.get('target'):
        raise ValueError('spec must declare exactly one delivery target')
    for key, allowed in [('host', ('github', 'gitlab', 'local', 'pending')),
                         ('delivery', ('local', 'draft', 'pr', 'merge')),
                         ('review', ('claude', 'local'))]:
        if key in fields and fields[key] not in allowed:
            raise ValueError(f'invalid {key} in spec')
    return fields


if __name__ == '__main__':
    try:
        print(json.dumps(read_spec(*sys.argv[1:])))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'codex-tuner contract: {error}')
