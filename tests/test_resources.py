#!/usr/bin/env python3
"""Real process/lease tests; bounded Docker adapter probes never contact a user's daemon."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(sys.argv.pop(1)).resolve()
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("resources", SCRIPT)
resources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resources)


def until(predicate, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    raise AssertionError("condition did not become true")


def alive(pid):
    result = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True)
    return result.returncode == 0 and not result.stdout.strip().startswith("Z")


class ResourcesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="atr-", dir="/tmp")
        self.root = Path(self.directory.name)
        self.sockets = self.root / "s"
        self.env = dict(os.environ, AGENT_TUNER_RESOURCE_DIR=str(self.root),
                        AGENT_TUNER_SOCKET_DIR=str(self.sockets))
        resources.ROOT = self.root
        resources.SOCKET_ROOT = self.sockets
        self.scopes = []
        self.checks = []

    def cli(self, *args, payload=None, ok=True):
        result = subprocess.run([sys.executable, str(SCRIPT), *args], env=self.env,
                                input=json.dumps(payload) if payload is not None else None,
                                capture_output=True, text=True, timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def scope(self, session="native-session-A"):
        scope = self.cli("open", "--session", session).stdout.strip()
        self.scopes.append(scope)
        return scope

    def start(self, scope, command=None):
        return json.loads(self.cli("start", scope, "--", *(command or ["sleep", "60"])).stdout)

    def state(self, scope):
        return json.loads((self.root / scope / "owner.json").read_text())

    def check(self, scope, code):
        process = subprocess.Popen([sys.executable, str(SCRIPT), "check", scope, "--",
                                    sys.executable, "-c", code], env=self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.checks.append(process)
        return process

    def tearDown(self):
        for process in self.checks:
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)
        for scope in self.scopes:
            self.cli("close", scope, ok=False)
        self.directory.cleanup()

    def test_closes_owned_tree_and_preserves_foreign_process(self):
        scope = self.scope()
        marker = self.root / "child"
        foreign = subprocess.Popen(["sleep", "60"])
        try:
            owned = self.start(scope, [sys.executable, "-c",
                "import subprocess,time; p=subprocess.Popen(['sleep','60']); "
                "open(%r,'w').write(str(p.pid)); time.sleep(60)" % str(marker)])
            until(lambda: marker.exists() and marker.read_text().isdigit())
            child = int(marker.read_text())
            self.assertIn("closed", self.cli("close", scope).stdout)
            until(lambda: not alive(owned["pid"]) and not alive(child))
            self.assertTrue(alive(foreign.pid))
            self.assertEqual(self.state(scope)["resources"], [])
        finally:
            foreign.terminate()
            foreign.wait()

    def test_ordinary_stop_does_not_finish_a_task(self):
        scope = self.scope()
        owned = self.start(scope)
        self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="Stop"))
        self.assertTrue(alive(owned["pid"]))
        self.assertFalse(self.state(scope)["closing"])

    def test_session_end_isolated_from_another_chat(self):
        first, second = self.scope(), self.scope("native-session-B")
        first_process, second_process = self.start(first), self.start(second)
        self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="SessionEnd"))
        until(lambda: not alive(first_process["pid"]))
        self.assertTrue(alive(second_process["pid"]))

    def test_active_check_defers_session_end_and_retries_on_completion(self):
        scope = self.scope()
        owned = self.start(scope)
        marker = self.root / "check-started"
        check = self.check(scope, "import time; open(%r,'w').write('yes'); time.sleep(1.2)" % str(marker))
        until(marker.exists)
        self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="SessionEnd"))
        self.assertTrue(alive(owned["pid"]))
        self.assertTrue(self.state(scope)["closing"])
        self.assertEqual(check.wait(timeout=8), 0)
        until(lambda: not alive(owned["pid"]))
        self.assertEqual(self.state(scope)["resources"], [])

    def test_killed_caller_does_not_drop_running_check_lease(self):
        scope = self.scope()
        owned = self.start(scope)
        marker, done = self.root / "running", self.root / "done"
        check = self.check(scope, "import time; open(%r,'w').write('yes'); time.sleep(1.2); "
                           "open(%r,'w').write('yes')" % (str(marker), str(done)))
        until(marker.exists)
        check.kill()
        check.wait()
        self.assertIn("deferred", self.cli("close", scope).stdout)
        self.assertTrue(alive(owned["pid"]))
        until(done.exists)
        until(lambda: self.state(scope)["resources"] == [])

    def test_launcher_exit_keeps_lease_for_its_worker(self):
        scope = self.scope()
        owned = self.start(scope)
        marker = self.root / "worker"
        check = self.check(scope, "import subprocess; subprocess.Popen(['sh','-c',%r], close_fds=True)"
                           % ("touch " + str(marker) + "; sleep 1.2"))
        until(marker.exists)
        self.assertIn("deferred", self.cli("close", scope).stdout)
        self.assertTrue(alive(owned["pid"]))
        self.assertEqual(check.wait(timeout=8), 0)
        until(lambda: not alive(owned["pid"]))

    def test_check_exit_code_passes_through(self):
        scope = self.scope()
        result = self.cli("check", scope, "--", sys.executable, "-c", "raise SystemExit(7)", ok=False)
        self.assertEqual(result.returncode, 7)

    def test_closed_scope_refuses_new_work(self):
        scope = self.scope()
        self.cli("close", scope)
        self.assertNotEqual(self.cli("start", scope, "--", "sleep", "60", ok=False).returncode, 0)
        self.assertNotEqual(self.cli("check", scope, "--", "true", ok=False).returncode, 0)

    def test_bad_scope_never_becomes_a_path(self):
        self.assertNotEqual(self.cli("close", "../foreign", ok=False).returncode, 0)

    def test_wrong_socket_token_does_not_stop_resource(self):
        scope = self.scope()
        owned = self.start(scope)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(resources.socket_path(owned["resource"])))
            connection.sendall(b"wrong-token")
        time.sleep(0.1)
        self.assertTrue(alive(owned["pid"]))

    def test_missing_supervisor_never_claims_cleanup_from_a_pid(self):
        scope = self.scope()
        path = self.root / scope
        data = self.state(scope)
        data["resources"].append(dict(kind="process", id="f" * 16, token="a" * 64, pid=os.getpid()))
        resources.save(path, data)
        result = self.cli("close", scope, ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lifetime unknown", result.stderr)
        self.assertEqual(len(self.state(scope)["resources"]), 1)
        data["resources"] = []
        resources.save(path, data)

    def test_process_observation_failure_preserves_the_lease(self):
        with patch.object(resources.subprocess, "run", side_effect=OSError("ps unavailable")):
            self.assertTrue(resources.members())

    def test_failed_launch_can_be_closed(self):
        scope = self.scope()
        self.assertNotEqual(self.cli("start", scope, "--", "/no-such-executable", ok=False).returncode, 0)
        self.cli("close", scope)
        self.assertEqual(self.state(scope)["resources"], [])

    def test_startup_context_and_empty_hooks(self):
        for event in ("Stop", "SessionEnd"):
            self.cli("hook", payload=dict(session_id="no-resources", hook_event_name=event))
        result = json.loads(self.cli("hook", payload=dict(session_id="native-123", hook_event_name="SessionStart")).stdout)
        self.assertIn("native-123", result["hookSpecificOutput"]["additionalContext"])

    def test_unreadable_scope_does_not_stop_other_cleanup(self):
        (self.root / ("d" * 32)).mkdir()  # Half-created: no owner.json yet.
        scope = self.scope()
        owned = self.start(scope)
        quiet = self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="Stop"))
        self.assertEqual(quiet.stderr, "")
        result = self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="SessionEnd"))
        until(lambda: not alive(owned["pid"]))
        self.assertIn("d" * 32, result.stderr)

    def test_wrong_shaped_record_does_not_stop_other_cleanup(self):
        broken = self.root / ("e" * 32)
        broken.mkdir()
        (broken / "owner.json").write_text("[]")  # Valid JSON, wrong shape.
        scope = self.scope()
        owned = self.start(scope)
        stop = dict(session_id="native-session-A", hook_event_name="Stop")
        self.assertEqual(self.cli("hook", payload=stop).stderr, "")  # Unattributable: SessionEnd reports it.
        self.cli("hook", payload=dict(stop, hook_event_name="SessionEnd"))
        until(lambda: not alive(owned["pid"]))

    def test_malformed_resource_fields_do_not_stop_other_cleanup(self):
        for name, resources_value in (("a" * 32, 1),
                                      ("b" * 32, [dict(kind="process", id=None, token="a" * 64)])):
            broken = self.root / name
            broken.mkdir()
            (broken / "owner.json").write_text(json.dumps(dict(
                version=1, session="native-session-A", closing=True, resources=resources_value)))
        scope = self.scope()
        owned = self.start(scope)
        result = self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="SessionEnd"))
        until(lambda: not alive(owned["pid"]))
        self.assertIn("a" * 32, result.stderr)
        self.assertIn("b" * 32, result.stderr)
        self.assertTrue((self.root / ("b" * 32) / "owner.json").exists())  # Preserved, not deleted.

    def test_every_form_of_auto_remove_is_refused(self):
        scope = self.scope()
        for argument in ("--rm", "--rm=true", "--rm=false"):
            with self.assertRaises(ValueError):
                resources.container(self.root / scope, [argument, "alpine"])

    def test_a_long_resource_root_still_starts_and_closes(self):
        deep = self.root / ("d" * 60) / ("e" * 60)
        deep.mkdir(parents=True)
        env = dict(self.env, AGENT_TUNER_RESOURCE_DIR=str(deep))
        def cli(*args):
            return subprocess.run([sys.executable, str(SCRIPT), *args], env=env,
                                  capture_output=True, text=True, timeout=15)
        scope = cli("open", "--session", "native-long").stdout.strip()
        started = cli("start", scope, "--", "sleep", "60")
        self.assertEqual(started.returncode, 0, started.stderr)
        pid = json.loads(started.stdout)["pid"]
        closed = cli("close", scope)
        self.assertIn("closed", closed.stdout, closed.stderr)
        until(lambda: not alive(pid))

    def test_close_racing_a_finishing_worker_still_closes(self):
        # A worker that is ending closes its socket before it removes the socket file and marks
        # the resource done; a close arriving in that gap must wait for the mark, not fail.
        for _ in range(8):
            scope = self.scope()
            self.start(scope, ["sleep", "0.2"])
            time.sleep(0.2)
            result = self.cli("close", scope, ok=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.state(scope)["resources"], [])

    def test_unexpected_docker_output_preserves_the_record(self):
        scope = self.scope()
        path = self.root / scope
        record = dict(kind="container", id="b" * 64, resource="c" * 16,
                      endpoint="unix:///local.sock", daemon="expected")
        data = self.state(scope)
        data["resources"].append(record)
        resources.save(path, data)
        def docker(arguments, endpoint=None):
            return "expected" if arguments[0] == "info" else "[]"
        with patch.object(resources, "docker", side_effect=docker):
            with self.assertRaises(RuntimeError):
                resources.close(path)
        self.assertEqual(len(self.state(scope)["resources"]), 1)
        data = self.state(scope)
        data["resources"] = []
        resources.save(path, data)

    def test_docker_timeout_message_is_stable(self):
        messages = []
        for seconds in (11.3, 7.1):
            with patch.object(resources.subprocess, "run",
                              side_effect=subprocess.TimeoutExpired(["docker", "info"], seconds)):
                with self.assertRaises(RuntimeError) as caught:
                    resources.docker(["info"])
            messages.append(str(caught.exception))
        self.assertEqual(messages[0], messages[1])

    def test_failure_seen_only_by_a_check_supervisor_reaches_the_hook(self):
        scope = self.scope()
        path = self.root / scope
        data = self.state(scope)
        data["closing"] = True
        data["resources"].append(dict(kind="process", id="f" * 16, token="a" * 64))
        resources.save(path, data)
        with self.assertRaises(RuntimeError):
            resources.close(path)  # What check_worker does, its stderr unseen.
        result = self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="Stop"))
        self.assertIn("lifetime unknown", result.stderr)
        data = self.state(scope)
        data["resources"] = []
        resources.save(path, data)

    def test_busy_scope_lock_stops_at_the_hook_deadline(self):
        import threading
        scope = self.scope()
        path = self.root / scope
        outcome = []
        with (path / "mutex").open("a+") as holder:
            resources.fcntl.flock(holder, resources.fcntl.LOCK_EX)
            def attempt():
                try:
                    with patch.object(resources, "DEADLINE", time.monotonic() + 1):
                        resources.close(path)
                except RuntimeError as error:
                    outcome.append(str(error))
            worker = threading.Thread(target=attempt, daemon=True)
            worker.start()
            worker.join(4)
            self.assertFalse(worker.is_alive())
        self.assertTrue(outcome and "budget" in outcome[0])

    def test_failing_cleanup_reports_once_per_reason(self):
        scope = self.scope()
        path = self.root / scope
        data = self.state(scope)
        data["closing"] = True
        data["resources"].append(dict(kind="process", id="f" * 16, token="a" * 64))
        resources.save(path, data)
        stop = dict(session_id="native-session-A", hook_event_name="Stop")
        first, second = self.cli("hook", payload=stop), self.cli("hook", payload=stop)
        self.assertIn("lifetime unknown", first.stderr)
        self.assertEqual(second.stderr, "")
        self.assertEqual(len(self.state(scope)["resources"]), 1)
        data = self.state(scope)
        data["resources"] = []
        resources.save(path, data)

    def test_detached_descendant_does_not_hold_the_check_lease(self):
        scope = self.scope()
        marker = self.root / "detached"
        # close_fds=False mirrors a shell's background job: it inherits every open descriptor.
        self.check(scope, "import subprocess; p=subprocess.Popen(['sleep','30'], start_new_session=True, "
                          "close_fds=False); open(%r,'w').write(str(p.pid))" % str(marker)).wait(timeout=10)
        until(lambda: marker.exists() and marker.read_text().isdigit())
        try:
            self.assertIn("closed", self.cli("close", scope).stdout)
        finally:
            os.kill(int(marker.read_text()), signal.SIGTERM)

    def test_startup_context_is_one_pointer_for_every_source(self):
        context = json.loads(self.cli("hook", payload=dict(
            session_id="native-123", hook_event_name="SessionStart")).stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("native-123", context)
        self.assertIn("references/resources.md", context)
        self.assertNotIn("heavy.sh", context)
        self.assertLess(len(context), 300)
        config = json.loads((SCRIPT.parent.parent / "hooks/hooks.json").read_text())
        self.assertTrue(all("matcher" not in group for group in config["hooks"]["SessionStart"]))

    def test_docker_calls_stop_at_the_hook_deadline(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        (bin_dir / "docker").write_text("#!/bin/sh\nsleep 10\n")
        (bin_dir / "docker").chmod(0o755)
        began = time.monotonic()
        with patch.dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"]), \
                patch.object(resources, "DEADLINE", time.monotonic() + 1):
            with self.assertRaises((RuntimeError, subprocess.SubprocessError)):
                resources.docker(["info"])
            with self.assertRaises(RuntimeError):
                resources.docker(["info"])
        self.assertLess(time.monotonic() - began, 4)

    def test_explicit_retention_survives_session_end(self):
        scope = self.scope()
        owned = self.start(scope)
        self.cli("retain", scope)
        self.cli("hook", payload=dict(session_id="native-session-A", hook_event_name="SessionEnd"))
        self.assertTrue(alive(owned["pid"]))
        self.assertFalse(self.state(scope)["closing"])

    def test_native_hook_commands_use_the_shipped_entrypoint(self):
        plugin = SCRIPT.parent.parent
        config = json.loads((plugin / "hooks/hooks.json").read_text())
        for event in ("SessionStart", "Stop", "SessionEnd"):
            commands = [hook["command"] for group in config["hooks"][event]
                        for hook in group["hooks"] if "resources.sh" in hook["command"]]
            self.assertEqual(len(commands), 1)
            env = dict(self.env, CLAUDE_PLUGIN_ROOT=str(plugin))
            result = subprocess.run(commands[0], shell=True, env=env,
                input=json.dumps(dict(hook_event_name=event, session_id="native-wire")),
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            if event == "SessionStart":
                context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
                self.assertIn(str(plugin / "references/resources.md"), context)

    def test_heavy_slots_shared_by_two_plugin_copies(self):
        import shutil
        heavy = SCRIPT.parent / "heavy.sh"
        other = self.root / "other-plugin-heavy.sh"
        shutil.copy2(heavy, other)
        log = self.root / "order"
        env = dict(self.env, CC_TUNER_HEAVY_DIR=str(self.root / "slots"), CC_TUNER_HEAVY_POLL="0.05", CC_TUNER_HEAVY_SLOTS="1")
        env.pop("CC_TUNER_HEAVY_HELD", None)
        first = subprocess.Popen(["bash", str(heavy), "--", "sh", "-c",
            'echo first-start >> "$1"; sleep .6; echo first-end >> "$1"', "sh", str(log)], env=env)
        try:
            until(lambda: log.exists() and "first-start" in log.read_text())
            second = subprocess.run(["bash", str(other), "--", "sh", "-c",
                'echo second-start >> "$1"', "sh", str(log)], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(first.wait(timeout=5), 0)
            self.assertEqual(log.read_text().splitlines(), ["first-start", "first-end", "second-start"])
        finally:
            first.wait(timeout=5)

    def test_docker_labels_before_image_and_no_volume_removal(self):
        scope = self.scope()
        path = self.root / scope
        calls, identifier = [], "a" * 64
        def docker(arguments, endpoint=None):
            calls.append(arguments)
            if arguments[0] == "create":
                return identifier
            if arguments[0] == "info":
                return "local-engine"
            if arguments[:2] == ["container", "inspect"]:
                record = self.state(scope)["resources"][0]
                return json.dumps([dict(Id=identifier, Config=dict(Labels={
                    resources.LABEL: scope, "dev.agent-tuner.resource": record["resource"]}))])
            return ""
        with patch.object(resources, "local_daemon", return_value=("unix:///local.sock", "local-engine")), patch.object(resources, "docker", side_effect=docker):
            resources.container(path, ["alpine:3", "sleep", "60"])
            create = calls[0]
            self.assertLess(create.index("--label"), create.index("alpine:3"))
            resources.close(path)
        self.assertIn(["rm", identifier], calls)
        self.assertFalse(any("-v" in call or "prune" in call or "--force" in call for call in calls))

    def test_docker_changed_owner_or_daemon_preserved(self):
        for mismatch in ("daemon", "labels"):
            scope = self.scope()
            path = self.root / scope
            record = dict(kind="container", id="b" * 64, resource="c" * 16,
                          endpoint="unix:///local.sock", daemon="expected")
            data = self.state(scope)
            data["resources"].append(record)
            resources.save(path, data)
            calls = []
            def docker(arguments, endpoint=None):
                calls.append(arguments)
                if arguments[0] == "info":
                    return "changed" if mismatch == "daemon" else "expected"
                return json.dumps([dict(Id=record["id"], Config=dict(Labels={}))])
            with patch.object(resources, "docker", side_effect=docker):
                with self.assertRaises((RuntimeError, ValueError)):
                    resources.close(path)
            self.assertFalse(any(call[0] in ("stop", "rm") for call in calls))
            data["resources"] = []  # Remove only the fake record so teardown never calls Docker.
            resources.save(path, data)

    def test_remote_docker_and_reserved_labels_refused(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(resources, "docker", return_value="ssh://remote"):
            with self.assertRaises(ValueError):
                resources.local_daemon()
        scope = self.scope()
        with self.assertRaises(ValueError):
            resources.container(self.root / scope, ["--label", "dev.agent-tuner.scope=foreign", "alpine"])


if __name__ == "__main__":
    unittest.main()
