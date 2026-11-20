# Acceptance evidence

Read before declaring a task verified or sending its candidate to review. The spec owns acceptance
criteria, the plan owns execution order, and the existing verification record connects the criteria
to observations. Write the record to a private scratch file outside the candidate. A clean committed candidate's first
line is `codex-tuner-verified: <full candidate SHA>`. For uncommitted work, identify the base and
actual worktree diff (including new files). Keep that record local. After a change, verify which
observations still apply and write the record for the new candidate. Publish the reviewed file as
evidence only when that write is authorized.

## Account for every criterion

1. Read the agreed criteria, the complete diff and affected consumers. For an audit, use the
   requested scope and report examined areas and remaining gaps in the existing audit report.
2. Map each criterion to a check or interaction that directly decides it. Read the repository's
   commands, fixtures and testing runbooks before choosing tools. A suite's success proves a
   criterion only when its assertions exercise that behaviour.
3. Inspect earlier results before running checks. Reuse them when the checked code, dependencies,
   configuration and environment still cover the candidate; name the source and why it applies.
   Re-run affected checks when inputs changed or evidence is missing or uncertain, and honour
   required fresh runs. Verification is not a second automatic full-suite pass.
4. Record each criterion, the command or interaction, the observed result, and the checked revision
   or worktree. One observation may cover several criteria. Keep failures, missing proof and
   user-accepted limitations visible beside the criterion they concern.

Use the instrument that observes the claim: browser interaction for a UI workflow, a real request
for an endpoint, persisted data for a save, competing clients for a concurrency guarantee. A test
can provide that evidence when it exercises the required path. Label fixtures, mocked dependencies,
static inspection and live observations accurately. A typecheck does not establish persistence,
and simulated events do not establish native browser behaviour.

Write the result as a compact table or the repository's existing record format:

| Criterion | Evidence and checked candidate | Result |
| --- | --- | --- |
| Saved edits survive reload | Browser save/reload and persisted value at `<revision>` | Observed value matches the edit |
| Concurrent saves preserve edits | Unit tests only at `<revision>` | NOT PROVED: competing clients and persistence were not exercised |

The reviewer reads this record with the spec and candidate and checks both coverage and whether
the evidence supports each claim. Resolve any gap that prevents the agreed outcome before claiming
completion; carry an explicitly accepted limitation with its user decision. Other gaps remain open
while independent work continues under run's existing delivery rules.

## Visual acceptance

Read the repository's design rules and the task's agreed reference or direction. Keep product
tokens, components and layout requirements in the repository; record the task's target screens,
states, roles and viewports in its spec, selecting only those affected by the change.

For a new visual direction or substantial redesign, inspect the reference's composition,
typography, density, colour and interaction or motion. Build and inspect one representative screen
with realistic content and shared chrome, or a short finished motion segment, before applying the
direction broadly. Resolve an unsettled visual choice with the user; an already agreed direction
does not need another approval.

For ordinary UI changes, inspect the changed screen against existing requirements. Exercise the
affected states and capture layout evidence through the repository's browser procedure. Compare
the rendered result with the agreed direction, record concrete discrepancies and fix them before
calling visual acceptance complete. For motion, inspect playback and transitions as well as frames.

Record visual observations separately from technical checks in the same acceptance record. Build,
accessibility checks and image snapshots prove their measured properties; they do not decide
composition, readability or fidelity to a reference. An unresolved human-only judgement keeps the
spec's existing `[eyes]` status and unattended-delivery restriction.
