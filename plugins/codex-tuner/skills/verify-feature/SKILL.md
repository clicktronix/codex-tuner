---
name: verify-feature
description: Verify an agreed outcome against the actual behaviour, including UI, persistence, recovery and cross-repository changes. Use during implementation or for a standalone verification request.
---

# Verify Feature

Read the task's acceptance criteria and [acceptance evidence](../../references/verification.md). Run the checks there that decide the affected behaviour. Reuse earlier results only when their inputs still match.

Record the candidate, environment and observation for each criterion in the existing verification record. Distinguish a passing assertion, an observed runtime result and an outstanding human decision. For a verification-only request, return the results and reproducible failures to the owner. During a run, fix authorized defects and recheck the affected criteria before handing the evidence to review.
