# Verification and resource readiness

Goal: make acceptance claims traceable to observed results, check resource availability before
heavy work, and compare visual work with its agreed direction inside the existing spec/run flow.

## Milestones

1. [x] Inspect the current skills, resource lifecycle and validation suite before choosing where the
   changes belong. The spec already owns acceptance; run owns verification and delivery.
2. [x] Connect each acceptance criterion to direct evidence and explicit gaps in the existing
   verification record. Review must consume that record before judging completion.
3. [x] Add a general resource-readiness check to the existing launch procedure. Preserve the shared
   heavy slots and resource ownership; avoid technology-specific capacity rules.
4. [x] Add visual comparison to specification and verification. Repository rules own design
   requirements; the task spec owns its reference and the required screens and states.
5. [x] Read the complete diff, trace representative cases through the instructions and run the
   repository suite once after the edits. Record results here so the final report names what was
   actually checked.

## Acceptance

- Every criterion has a direct observation or an explicit missing proof in the existing record;
  tests, fixtures and actual runtime observations retain their distinct meanings.
- Earlier results are reused when their inputs still cover the candidate; these changes introduce
  no commit/push hook, extra full-suite cadence, separate task journal or new acceptance document.
- Heavy work checks available memory, CPU headroom and free space against its needs, waits when
  capacity is insufficient, and rechecks after waiting without stopping other tasks.
- A new visual direction is checked on a representative result before broad application; ordinary
  UI changes use existing design requirements. Technical checks do not decide visual quality.
- Changes stay in codex-tuner. Cars, session budgets and review caps are outside this task.

## Verification

- Review spec/run/task-flow and their references against the criteria above and these cases:
  a synchronization change with unit evidence only; reused unchanged evidence; an audit with unread
  paths; a busy host; a new visual direction; an ordinary UI fix.
- Check local Markdown targets and validate the edited skills with the installed skill validator.
- Full repository gate: `bash tests/run.sh`.
- No model eval, preview, live service, publication or installation is needed for this prose change.

## Results

- Reviewed every changed skill passage and both reference files. The original spec/run required
  checks but did not define the acceptance evidence record or visual comparison; the original
  resource procedure limited concurrency without assessing capacity.
- Traced six cases through the revised instructions:
  - Unit-only evidence for synchronization remains unproved until the claimed path is exercised.
  - Unchanged relevant evidence is reused with its source; verification adds no automatic rerun.
  - An audit names unread paths and untested scenarios in its existing report.
  - A busy host is checked inside the slot before launch; insufficient capacity releases the slot
    and waits without stopping another task.
  - A new visual direction uses a representative rendered result before broad application.
  - An ordinary UI fix follows repository design requirements without another direction approval.
- All three edited skills pass `skill-creator/scripts/quick_validate.py`, using an isolated uv
  environment for its PyYAML dependency. The system Python lacks that dependency.
- Seven local Markdown links and anchors resolve; `git diff --check` passes.
- Full repository gate: `bash tests/run.sh` passed once through `heavy.sh`, including 21 setup
  tests, contract/merge/PR-title checks, 35 resource tests and structure mutation checks.
- Waited for another task's shared heavy slot. After acquiring it, observed 48% available memory,
  load average 2.85 on 10 logical CPUs and about 20 GB free space. That was sufficient for this
  small validation suite; no other task was stopped.
- Validation covers the plugin's existing executable contracts and the edited prose's structure
  and links. Model adherence to the new instructions has not been measured by an eval.
