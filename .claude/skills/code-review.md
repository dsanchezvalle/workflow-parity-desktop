<!-- CORE: agnostic -->
---
name: code-review
description: Review a plan (mode=plan, pre-implementation) or implemented code (mode=code, pre-merge). Use when the user says "review the plan", "review my code", or as part of the start orchestration.
---

# code-review

Two strict modes. The mode is required — refuse to run without it.

## Mode `plan` — pre-implementation

Read the issue, the plan comment, and the relevant existing code. Decide if
the plan is safe to execute as written.

Checks:

- **Architectural fit** — does the plan respect existing module boundaries
  and naming conventions? Look at neighbors of the files being touched.
- **Anti-overengineering** — flag speculative abstractions, premature
  generalization, helpers introduced for one caller, config knobs with no
  current consumer, parallel implementations of something that already
  exists.
- **Scope discipline** — does the plan match the issue, or does it grow new
  scope? "While we're here, let's also..." is a red flag.
- **Test gaps** — does the plan say how the change is verified? Unit at
  minimum; integration if I/O, network, or DB are involved.
- **Rollback** — for E2/E3, the plan must say how to undo this if it breaks.
- **Reuse** — is there a function, hook, or utility already in the repo that
  does most of this? If yes, name it.

Output: `APPROVE` or `REQUEST CHANGES`, followed by line items. Each item
either references a plan bullet or a file path.

## Mode `code` — pre-merge

Read the diff, the approved plan, and the touched files in their entirety
where size permits.

Checks:

- **Plan alignment** — implementation matches the approved plan. Any
  deviation must be called out and justified in the PR body.
- **Security** (apply at every boundary):
  - input validated where untrusted data enters,
  - secrets not logged, not committed, not in error messages,
  - authz checks present for every protected operation,
  - no SQL/NoSQL/template/command injection sinks,
  - error messages do not leak internals.
- **Performance** (defensible defaults, not premature optimization):
  - no obvious N+1 in loops over collections,
  - no unbounded fetches from external systems,
  - no synchronous I/O on a hot path,
  - cache invalidation is correct if a cache is touched.
- **Correctness**:
  - error handling at boundaries (not internal, where it adds noise),
  - edge cases listed in the plan are tested,
  - no dead code, no TODOs without an issue link.
- **Conventional Commits** — every commit on the branch follows the format.
  Squash-on-merge counts: PR title must also be conventional.
- **Tests** — added or updated tests cover the change. Run them locally;
  paste output in the PR.

Output: `APPROVE` or `REQUEST CHANGES`, with line items keyed to file:line.

## Hard rules

- Never approve a plan that introduces an abstraction with one caller.
- Never approve code without seeing test output.
- Never approve a `code` review if `plan` mode was skipped.
- If the diff and the plan disagree, the plan wins — request changes.
