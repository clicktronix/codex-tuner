# Task resources

Read before launching a preview, a dedicated MCP server, disposable test services, or checks that
consume them. Use existing fixture teardown / `finally` / shell traps first. The helper covers
task-owned background lifetimes across tool calls; it is not a plan or delivery journal.

Two terms below: a **scope** is one task's ownership record, created by `open` and named by the
ID it prints; a **lease** is the kernel lock a running `check` holds, which makes `close` wait.

Resolve `<plugin-root>` from this installed plugin, not a guessed cache version. Hooks supply
`Resource session <id>` at SessionStart. Use that native identity; if the hook is unavailable,
keep work in the foreground with repository teardown rather than inventing session ownership.

```bash
python3 <plugin-root>/scripts/resources.py open --session <id>
# Save the returned <scope> in the task's working context, and pass it to every consumer.
python3 <plugin-root>/scripts/resources.py start <scope> -- npm run dev
python3 <plugin-root>/scripts/resources.py check <scope> -- <verification-command> <args>
python3 <plugin-root>/scripts/resources.py close <scope>
```

Scopes live under `~/.cache/agent-tuner/resources` (override: `AGENT_TUNER_RESOURCE_DIR`).
`status <scope>` prints a scope's ownership record.

`start` prints its log path and resource ID. It creates an isolated process group under a small
supervisor. Close reaches that supervisor through a private authenticated socket, kept in a short
private directory `/tmp/atr-<uid>` (override: `AGENT_TUNER_SOCKET_DIR`; it must be a mode-0700
directory of the current user) rather than in the scope. Close never adopts or signals a PID
discovered in the machine's process list. The supervisor also follows workers
whose launcher exits. Keep processes in that group: a server that daemonizes into another session
needs its own supported lifecycle and must remain outside this helper.

Every check using these services runs through `check` with the **same scope**, including consumers
in another agent. Its supervisor holds a kernel lease until the command and its process group finish,
even if the calling tool process dies. Close records the request and defers while any lease is held;
the final check retries cleanup. There is no age/heartbeat timeout. An interrupt of the caller does
not cancel detached verification: report its scope, and use the repository's cancellation mechanism
only when cancellation is authorized. Commands that detach into another session must await their
own workers or use their existing fixture lifecycle instead.

Use the tuner's `scripts/heavy.sh` for full builds/suites, e2e and service starts. Both tuners use
the same `CC_TUNER_HEAVY_*` settings (`SLOTS`, default 1; `DIR`, default `~/.cache/cc-tuner/heavy`;
`POLL`, default 2 s) and lock directory, so they queue across clients. For a heavy check using this
scope, put `check` around the actual foreground runner inside the heavy slot:

```bash
bash <plugin-root>/scripts/heavy.sh --label "<repo>: e2e" -- \
  python3 <plugin-root>/scripts/resources.py check <scope> -- <foreground-e2e-runner>
```

For a **new disposable** test container, the helper creates it with scope/resource labels, records
its full ID and local daemon identity before starting it, then stops/removes that exact container
at close. Pass ordinary `docker create` options before IMAGE; ensure ports and names are task-specific.
Every form of `--rm`, plus `--label-file` and any `dev.agent-tuner.` label, is refused: the helper
owns disposal and ownership labels, and Docker removing the container itself would leave close
with an unknown record and could drop anonymous volumes:

```bash
python3 <plugin-root>/scripts/resources.py container <scope> -- --name <unique-name> <image> <args>
```

Only a local Unix Docker context without endpoint overrides is accepted. Existing Compose stacks,
project databases, Ryuk/Testcontainers resources and shared services keep their native owner and
teardown. Do not adopt them or use global stop/prune. The helper never removes volumes or images.
If the fixture supports labels, label its resources with the task identity and still use fixture
teardown; labels alone do not register them with this helper.

Close once consumers finish, **before the final answer**, also when delivery is blocked, cancelled,
or handed back without a merge. Stop retries only already-requested cleanup; it does not decide
that a response ends the task. Stop closes only scopes already marked closing; SessionEnd closes
every non-retained scope of that session as a fallback. Both hooks stop after a 25 s deadline (the
hook timeout is 30 s) and leave unfinished cleanup for the next Stop. A scope whose ownership record
is malformed is preserved untouched and reported at SessionEnd; one bad scope does not stop the
others. Codex may wait until a closed conversation has been idle for 30 minutes, so that fallback is not prompt
task cleanup. A missing lifecycle event or SIGKILL is not a cleanup guarantee.

If the user explicitly wants a preview left running, `retain <scope>` exempts it from automatic
session cleanup. Report its scope, URL and `close <scope>` command. Otherwise report `closed`,
`deferred: active checks`, or the concrete cleanup failure; TERM-resistant processes are preserved
and reported. Retained or deferred work is not reclaimed memory.

Client-managed MCP transports belong to the client. Leave them to its supported disconnect/reload
and session lifecycle; never kill cohorts by cwd, start time, age or port. A dedicated MCP server
explicitly started through `start` follows this scope like a preview. Existing unregistered
processes are unaffected. If Python or hook trust is unavailable, state that automatic cleanup is
unavailable and keep the foreground/fixture teardown path.
