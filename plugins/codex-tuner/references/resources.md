# Task resources

Read before launching a preview, a dedicated MCP server, disposable test services, a heavy check, or
checks that consume them. Use existing fixture teardown / `finally` / shell traps first. The helper covers
task-owned background lifetimes across tool calls.

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

`start` prints its log path and resource ID and runs the command in its own process group under a
supervisor that also follows workers whose launcher exits. Close reaches the supervisor through a
private socket (directory override: `AGENT_TUNER_SOCKET_DIR`). Keep processes in that group: a server
that daemonizes into another session needs its own lifecycle and stays outside this helper.

Every check using these services runs through `check` with the **same scope**, including consumers
in another agent. Its supervisor holds a kernel lease until the command and its process group finish,
even if the calling tool process dies. Close records the request and defers while any lease is held;
the final check retries cleanup. An interrupt of the caller does
not cancel detached verification: report its scope, and use the repository's cancellation mechanism
only when cancellation is authorized.

## Concurrent tasks

Before reusing a branch or checkout, inspect `git worktree list --porcelain`, its status and the task's existing PR or MR. A worktree entry identifies a checkout. Use available session or task context to establish who is working in it. Preserve unfamiliar edits and running services. Give independent tasks distinct worktrees, paths and resource scopes. When ownership overlaps, continue on disjoint work and resolve the specific conflict with its owner.

## Heavy checks

A full build, the full test suite, an e2e suite and a container start run through the machine's
slots. `scripts/heavy.sh` is the same file as cc-tuner's, so both plugins share one queue:

```bash
bash <plugin-root>/scripts/heavy.sh --weight <w> --label "<repo>: <what>" -- <runner>
```

An e2e suite takes `--weight 2`; a full suite, build or container start takes the default weight 1.
Capacity follows the machine's RAM and waiters start in arrival order, so the call may wait. Start
it as a background job, keep working, then wait on that job for its result. The runner's output and
exit code pass through; heavy.sh's own refusals exit 64. The helper itself waits out memory
pressure, within a bound. Carry into the report every output line that starts with
`heavy.sh: started under memory pressure`, `heavy.sh: memory pressure not measured` or
`heavy.sh: started without a slot`: a failure in that run may be the machine, not the code. Do not
stop another task's work to free a slot.

For a heavy check using a scope, `check` goes inside the slot:

```bash
bash <plugin-root>/scripts/heavy.sh --weight 2 --label "<repo>: e2e" -- \
  python3 <plugin-root>/scripts/resources.py check <scope> -- <e2e-runner>
```

## Disposable test containers

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
or handed back without a merge. The Stop and SessionEnd hooks are fallbacks, not prompt cleanup:
Stop retries only scopes already marked closing, SessionEnd closes every non-retained scope of the
session, and Codex may delay it until a closed conversation has been idle for 30 minutes. A missing
lifecycle event or SIGKILL is not a cleanup guarantee.

If the user explicitly wants a preview left running, `retain <scope>` exempts it from automatic
session cleanup. Report its scope, URL and `close <scope>` command. Otherwise report `closed`,
`deferred: active checks`, or the concrete cleanup failure; TERM-resistant processes are preserved
and reported. Retained or deferred work is not reclaimed memory.

Client-managed MCP transports belong to the client. Leave them to its supported disconnect/reload
and session lifecycle; never kill cohorts by cwd, start time, age or port. A dedicated MCP server
explicitly started through `start` follows this scope like a preview. If Python or hook trust is unavailable, state that automatic cleanup is
unavailable and keep the foreground/fixture teardown path.
