#!/usr/bin/env python3
"""Own only resources created here; close a task without interrupting its checks.

Python standard library, macOS/Linux. No process discovery,
PID adoption, Docker pruning, workflow state, or model calls. See references/resources.md.
"""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import select
import signal
import socket
import subprocess
import sys
import time


ROOT = Path(os.environ.get("AGENT_TUNER_RESOURCE_DIR", "~/.cache/agent-tuner/resources")).expanduser()
SCRIPT = str(Path(__file__).resolve())
LABEL = "dev.agent-tuner.scope"
# A hook sets this below its own timeout, so a slow daemon leaves the record for the next Stop
# instead of the hook being killed halfway through a close.
DEADLINE = None
FAILURES = (OSError, ValueError, RuntimeError, subprocess.SubprocessError)
DOCKER_ENV = ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH")
RECORD_FILES = (".json", ".sock", ".log", ".done")


def remaining(limit):
    """Seconds a wait may take: `limit`, cut to what is left of a hook's DEADLINE."""
    if DEADLINE is None:
        return limit
    left = DEADLINE - time.monotonic()
    if left < 0.5:
        raise RuntimeError("hook time budget spent; cleanup retries on the next Stop")
    return min(limit, left)


def is_scope_dir(path):
    return bool(re.fullmatch(r"[a-f0-9]{32}", path.name)) and not path.is_symlink() and path.is_dir()


def scope_path(scope):
    if not re.fullmatch(r"[a-f0-9]{32}", scope):
        raise ValueError("invalid resource scope")
    path = ROOT / scope
    if not is_scope_dir(path):
        raise ValueError("unknown resource scope")
    return path


@contextlib.contextmanager
def locked(path):
    with (path / "mutex").open("a+") as mutex:
        while True:
            try:
                fcntl.flock(mutex, fcntl.LOCK_EX | (fcntl.LOCK_NB if DEADLINE is not None else 0))
                break
            except BlockingIOError:
                remaining(1)  # Raises once a hook's budget is spent.
                time.sleep(0.1)
        yield


def read(path):
    with (path / "owner.json").open() as file:
        data = json.load(file)
    if not isinstance(data, dict) or not all(isinstance(record, dict) for record in data.get("resources") or []):
        raise ValueError("invalid ownership record")
    if (data.get("version") != 1 or not isinstance(data.get("resources"), list)
            or not isinstance(data.get("session"), str) or type(data.get("closing")) is not bool):
        raise ValueError("invalid ownership record")
    for record in data["resources"]:
        length = 16 if record.get("kind") == "process" else 64
        if not re.fullmatch(r"[a-f0-9]{%d}" % length, record.get("id", "")):
            raise ValueError("invalid resource identity")
    return data


def save(path, data):
    temporary = path / "owner.tmp"
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path / "owner.json")


def new_scope(session):
    if not session or len(session) > 256:
        raise ValueError("a native session identity is required")
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    if ROOT.is_symlink() or ROOT.stat().st_uid != os.getuid():
        raise ValueError("resource directory must be owned by the current user")
    ROOT.chmod(0o700)
    path = ROOT / secrets.token_hex(16)
    path.mkdir(mode=0o700)
    save(path, dict(version=1, session=session, cwd=os.getcwd(), closing=False, resources=[]))
    return path.name


def members():
    try:
        result = subprocess.run(["ps", "-A", "-o", "pid=,pgid=,stat="],
                                capture_output=True, text=True, check=True, timeout=3,
                                start_new_session=True)
    except (OSError, subprocess.SubprocessError):
        return [os.getpid()]  # Unknown is busy; retain the check lease and resource record.
    group = str(os.getpgrp())
    return [int(parts[0]) for parts in map(str.split, result.stdout.splitlines())
            if len(parts) == 3 and parts[1] == group and int(parts[0]) != os.getpid()
            and not parts[2].startswith("Z")]


def wait_group(child):
    code = child.wait()
    # A launcher may exit before its workers. Keep the lifetime/lease with the group.
    while members():
        time.sleep(0.25)
    return code if code >= 0 else 128 - code


def terminate_group():
    # Called only by the group's own supervisor, never from a recorded PID.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    os.killpg(os.getpgrp(), signal.SIGTERM)
    deadline = time.monotonic() + 1.5
    while members() and time.monotonic() < deadline:
        time.sleep(0.05)
    return not members()


def worker(path, resource, command, ready_fd, server_fd):
    """A private socket authenticates close; foreign/reused PIDs are never signalled."""
    endpoint = path / (resource + ".sock")
    record = json.loads((path / (resource + ".json")).read_text())
    server = socket.socket(fileno=server_fd)
    child = None
    try:
        server.settimeout(0.25)
        child = subprocess.Popen(command)
        os.write(ready_fd, b"1")
        os.close(ready_fd)
        while True:
            try:
                connection, _ = server.accept()
                with connection:
                    connection.settimeout(1)
                    if connection.recv(256).decode() == record["token"]:
                        if terminate_group():
                            break
            except socket.timeout:
                pass
            if child.poll() is not None and not members():
                break
    finally:
        if child is not None and child.poll() is None:
            terminate_group()
        server.close()
        if child is None or not members():
            (path / (resource + ".done")).touch()
            endpoint.unlink(missing_ok=True)


def start(path, command):
    with locked(path):
        data = read(path)
        if data["closing"]:
            raise ValueError("scope is closing; open a new task scope")
        resource = secrets.token_hex(8)
        record = dict(kind="process", id=resource, token=secrets.token_hex(32))
        (path / (resource + ".json")).write_text(json.dumps(record))
        # Register before starting; a killed launcher cannot leave an unregistered child.
        data["resources"].append(record)
        save(path, data)
        incoming, outgoing = os.pipe()
        server = socket.socket(socket.AF_UNIX)
        try:
            server.bind(str(path / (resource + ".sock")))
            server.listen(2)
            with (path / (resource + ".log")).open("ab") as log:
                child = subprocess.Popen([sys.executable, SCRIPT, "_worker", path.name,
                                          resource, str(outgoing), str(server.fileno()), "--", *command],
                                         start_new_session=True, pass_fds=(outgoing, server.fileno()),
                                         stdin=subprocess.DEVNULL, stdout=log, stderr=log)
            os.close(outgoing)
            outgoing = None
            if not select.select([incoming], [], [], 5)[0] or os.read(incoming, 1) != b"1":
                raise RuntimeError("resource did not start; inspect " + str(path / (resource + ".log")))
        finally:
            server.close()
            os.close(incoming)
            if outgoing is not None:
                os.close(outgoing)
        return dict(scope=path.name, resource=resource, log=str(path / (resource + ".log")), pid=child.pid)


def docker(arguments, endpoint=None):
    env = {key: value for key, value in os.environ.items() if key not in DOCKER_ENV}
    prefix = ["docker", "--host", endpoint] if endpoint else ["docker"]
    try:
        return subprocess.run([*prefix, *arguments], env=env, capture_output=True,
                              text=True, check=True, timeout=remaining(12)).stdout.strip()
    except subprocess.TimeoutExpired:
        # A stable message, so a hook reports a repeated timeout once.
        raise RuntimeError("docker " + arguments[0] + " timed out") from None


def local_daemon():
    if any(os.environ.get(key) for key in DOCKER_ENV):
        raise ValueError("use a local Docker context without endpoint overrides")
    endpoint = docker(["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"])
    if not endpoint.startswith("unix://"):
        raise ValueError("only a local Unix Docker socket can own disposable containers")
    return endpoint, docker(["info", "--format", "{{.ID}}"], endpoint)


def container(path, arguments):
    # Use a dedicated disposable container; never adopt Compose/project databases.
    if any(arg in ("--rm", "--label-file") or arg.startswith("--label-file=")
           or "dev.agent-tuner." in arg for arg in arguments):
        raise ValueError("disposal and ownership labels are managed by the resource helper")
    endpoint, daemon = local_daemon()
    with locked(path):
        data = read(path)
        if data["closing"]:
            raise ValueError("scope is closing")
        resource = secrets.token_hex(8)
        identifier = docker(["create", "--label", LABEL + "=" + path.name,
                             "--label", "dev.agent-tuner.resource=" + resource, *arguments], endpoint)
        if not re.fullmatch(r"[a-f0-9]{64}", identifier):
            raise ValueError("Docker did not return a full container ID")
        data["resources"].append(dict(kind="container", id=identifier, resource=resource,
                                      endpoint=endpoint, daemon=daemon))
        save(path, data)
        docker(["start", identifier], endpoint)
        return identifier


def stop_resource(path, record):
    if record["kind"] == "process":
        endpoint = path / (record["id"] + ".sock")
        if not endpoint.exists():
            if (path / (record["id"] + ".done")).exists():
                return
            raise RuntimeError("process lifetime unknown; preserved " + record["id"])
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(remaining(2))
            connection.connect(str(endpoint))
            connection.sendall(record["token"].encode())
        deadline = time.monotonic() + remaining(4)
        while endpoint.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        if endpoint.exists() or not (path / (record["id"] + ".done")).exists():
            raise RuntimeError("process cleanup unconfirmed: " + record["id"])
    elif record["kind"] == "container":
        endpoint = record["endpoint"]
        if not endpoint.startswith("unix://") or docker(["info", "--format", "{{.ID}}"], endpoint) != record["daemon"]:
            raise ValueError("Docker daemon identity changed; preserved " + record["id"])
        try:
            result = json.loads(docker(["container", "inspect", record["id"]], endpoint))[0]
            identity, labels = result["Id"], result.get("Config", {}).get("Labels") or {}
        except (IndexError, KeyError, TypeError, AttributeError) as error:
            raise ValueError("unexpected docker inspect output; preserved " + record["id"]) from error
        if (identity != record["id"] or labels.get(LABEL) != path.name
                or labels.get("dev.agent-tuner.resource") != record["resource"]):
            raise ValueError("Docker ownership changed; preserved " + record["id"])
        docker(["stop", "--time", "2", record["id"]], endpoint)
        docker(["rm", record["id"]], endpoint)  # Deliberately no -v, force or prune.
    else:
        raise ValueError("unknown resource kind")


def close(path):
    with locked(path):
        data = read(path)
        data["closing"] = True
        save(path, data)
        with (path / "checks").open("a+") as lease:
            try:
                fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return "deferred: active checks"
            failures = []
            for record in list(data["resources"]):
                try:
                    stop_resource(path, record)
                except FAILURES as error:
                    failures.append(str(error))
                    continue
                data["resources"].remove(record)
                for suffix in RECORD_FILES:
                    (path / (record["id"] + suffix)).unlink(missing_ok=True)
                save(path, data)
            if failures:
                raise RuntimeError("; ".join(failures))
            return "closed"


def check(path, command):
    with locked(path):
        if read(path)["closing"]:
            raise ValueError("scope is closing; no new checks")
        lease = (path / "checks").open("a+")
        fcntl.flock(lease, fcntl.LOCK_SH)
        child = subprocess.Popen([sys.executable, SCRIPT, "_check", path.name,
                                  str(lease.fileno()), "--", *command],
                                 pass_fds=(lease.fileno(),), start_new_session=True)
        lease.close()  # The supervisor keeps the lease even if this caller is killed.
    return child.wait()


def check_worker(path, descriptor, command):
    try:
        return wait_group(subprocess.Popen(command))
    finally:
        os.close(descriptor)
        if read(path)["closing"]:
            try:
                close(path)
            except FAILURES as error:
                print("resources: " + str(error), file=sys.stderr)


def hook():
    payload = json.load(sys.stdin)
    session = payload.get("session_id")
    event = payload.get("hook_event_name")
    if not session:
        return
    if event == "SessionStart":
        context = ("Resource session " + session + ": before starting a preview, dedicated MCP server or "
                   "disposable container, read " + str(Path(SCRIPT).parent.parent / "references/resources.md") + ".")
        print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": context}}))
    elif event in ("Stop", "SessionEnd") and ROOT.exists():
        global DEADLINE
        DEADLINE = time.monotonic() + 25  # The hook's own timeout is 30 s.
        problems = []
        for path in sorted(ROOT.iterdir()):
            if not is_scope_dir(path):
                continue
            # One scope's failure must not stop the others, nor repeat after every response.
            try:
                data = read(path)
            except FAILURES as error:
                if event == "SessionEnd":  # Unattributable to a session: report it once, at its end.
                    problems.append(path.name + ": " + str(error))
                continue
            if (data["session"] != session or data.get("retained")
                    or not (event == "SessionEnd" or data["closing"])):
                continue
            try:
                close(path)
            except FAILURES as error:
                if str(error) != data.get("reported"):
                    problems.append(path.name + ": " + str(error))
                    remember_reported(path, str(error))
        for problem in problems:
            print("resources: " + problem, file=sys.stderr)


def remember_reported(path, message):
    try:
        with locked(path):
            data = read(path)
            data["reported"] = message
            save(path, data)
    except FAILURES:
        pass  # Unrecorded only means the same failure is reported again next Stop.


def retain(path):
    with locked(path):
        data = read(path)
        if data["closing"]:
            raise ValueError("cannot retain a closing scope")
        data["retained"] = True
        save(path, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("open", "start", "check", "container", "close", "retain", "status", "hook", "_worker", "_check"))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    rest = args.arguments
    if args.action == "hook":
        hook()
        return 0
    if args.action == "open":
        if len(rest) != 2 or rest[0] != "--session":
            raise ValueError("open --session <native-session-id>")
        print(new_scope(rest[1]))
        return 0
    if not rest:
        raise ValueError("a resource scope is required")
    path = scope_path(rest.pop(0))
    if args.action in ("_worker", "_check"):
        identifier = rest.pop(0)
        descriptor = int(rest.pop(0)) if args.action == "_worker" else int(identifier)
        server_fd = int(rest.pop(0)) if args.action == "_worker" else None
    if rest and rest[0] == "--":
        rest.pop(0)
    if args.action in ("start", "check", "container", "_worker", "_check") and not rest:
        raise ValueError("a command or container image is required after --")
    if args.action == "start":
        print(json.dumps(start(path, rest)))
    elif args.action == "check":
        return check(path, rest)
    elif args.action == "container":
        print(container(path, rest))
    elif args.action == "_worker":
        worker(path, identifier, rest, descriptor, server_fd)
    elif args.action == "_check":
        return check_worker(path, descriptor, rest)
    elif args.action == "close":
        print(close(path))
    elif args.action == "retain":
        retain(path)
        print("retained: report this scope and its manual close command to the user")
    else:
        print(json.dumps(read(path), indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except FAILURES as error:
        print("resources: " + str(error), file=sys.stderr)
        sys.exit(1)
