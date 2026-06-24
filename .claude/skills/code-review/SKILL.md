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

## Comment precedence (anti-anchoring)

The issue/PR comment thread is not background — it is the **current state of
the agreement**. The original `analyze` plan is the opening proposal, not the
final contract. Later comments that record an **accepted** decision supersede it. The
**canonical record** of such a decision is a `[decision]` breadcrumb on every
surface that exists when the decision is taken — always the issue, and the PR
once `auto-pr` opens it (per AGENTS.md → Decision-breadcrumb convention),
required for any post-plan trajectory change:

- an explicit scope adjustment (item added or dropped),
- a business clarification from review that changes acceptance criteria,
- an acted-on `REQUEST CHANGES` iteration.

This matters most on a **`code`-mode re-review** — a second pass after a prior
`REQUEST CHANGES`. Before flagging a divergence from the plan as a blocker,
scan every comment posted after the most recent `code-review` (or after the
approved plan if there is no prior review). If the thing you are about to flag
was already accepted as a scope extension, declared out-of-scope with a
reason, or explicitly deferred — **do not raise it** as a blocker. At most,
note under minor items that the diff diverges from what the comment promised.
Only re-raise a settled item if the diff **explicitly contradicts** the later
agreement.

This guards a concrete failure mode: anchoring on the frozen original plan and
re-flagging accepted scope extensions as blockers on every subsequent pass.
The `[decision]` breadcrumbs that `start` and `code-review` already post (see
*Decision breadcrumbs* below) are precisely the record to honor here — produce
them on one pass, consume them on the next.

**Honoring a decision is not a license to skip its breadcrumb** — but require
it only on the **surfaces that exist when you review**. Per the canonical flow,
`code-review` runs at steps 3/5, *before* `start` pushes and `auto-pr` opens the
PR at step 8 (AGENTS.md → End-to-end flow): the **issue always exists; the PR
may not yet**. So:

- **Always require the breadcrumb on the issue.** A trajectory-changing decision
  recorded only in an ordinary comment (or absent) has not satisfied the
  convention → request it before approving.
- **If the PR already exists** (a post-push re-review), require the same
  `[decision]` text on the PR too.
- **If the PR does not exist yet**, the issue breadcrumb is sufficient to
  approve; the PR copy is posted when `start` opens the PR (per AGENTS.md →
  Decision-breadcrumb convention), not demanded now.

Suppress the *scope* blocker (the change was accepted), but do not approve a
state whose decision is missing from the surface(s) that exist.

## Hard rules

- Never approve a plan that introduces an abstraction with one caller.
- Never approve code without seeing test output.
- Never approve a `code` review if `plan` mode was skipped.
- If the diff diverges from the **current agreement** — the approved plan plus
  any later accepted decisions (see *Comment precedence*) — and **no**
  `[decision]` breadcrumb records that divergence, the agreement wins: request
  changes. An **undocumented** divergence always loses. A divergence accepted
  in the thread is not a *scope* blocker — but if its `[decision]` breadcrumb is
  missing from a surface that exists at review time (always the issue; the PR
  once opened), request the breadcrumb before approving.

## Decision breadcrumbs

When this review returns `REQUEST CHANGES` and the change is acted on
(i.e. the next pass differs from the previous diff in response to the
findings), post a concise `[decision]` comment on every surface that exists
when the decision is taken — always the issue, and the PR once `auto-pr` opens
it (pre-push, the issue alone suffices; the PR copy is mirrored when it opens)
— per AGENTS.md → Decision-breadcrumb convention. Same text on each surface.
One or two lines, format `[decision] <what changed> — <why>.`

## External reviewer — context delivery (reviewer-agnostic)

The pack's own reviewer is this `code-review` skill (Claude). Separately,
you may want an **external** reviewer — a second opinion or a human-driven
pass with whatever tool you prefer. The pack does not invoke one and does
not depend on any: that step is yours, outside the workflow.

When you do reach for an external reviewer, the diff alone is not enough —
it cannot judge plan alignment, scope discipline, or workflow-rule
compliance without `AGENTS.md`, the issue body, and the approved plan.
Use the `review-pack` skill to assemble a neutral REVIEW CONTEXT PACKET
(issue + PR metadata, rules, approved plan, changed files, checks) and hand
that packet to whatever reviewer you use. `review-pack` only prepares
context — it never invokes a tool, posts a comment, or pushes.

Without that context, an external reviewer's verdict depth will trail this
skill's on the same diff: it will catch raw correctness bugs but miss
workflow-compliance blockers (approval gate, verification body, scope
creep) that depend on rules only present in the packet.

## External reviewer bot — handling its comments

A repo may also wire an **external reviewer bot** (e.g. the Codex GitHub app)
that comments on the PR — automatically on every PR, or on demand with
`@codex review`. The pack neither installs nor requires it (it stays
reviewer-agnostic); when one is present, treat its output as an **independent
reviewer**, not an authority:

- **Judge each comment with full context** — the issue, the approved plan,
  `AGENTS.md`, and the *Comment precedence* rule above. A bot sees the diff; it
  does not always see the workflow rules or an already-accepted `[decision]`.
- **Never auto-apply.** A bot finding is a suggestion, not a directive.
- **Decline with a reason when warranted** — a design or architecture decision
  forbids the change, it duplicates an accepted scope decision, or it simply
  isn't pertinent. Record the reason where the decision belongs (a PR reply, or
  a `[decision]` breadcrumb if it changes trajectory).

This keeps the second reviewer valuable (the independence/diversity axis)
without ceding the executor's judgment to it.

## MCP / web-session overrides

In a web/mobile session (no authenticated `gh`, and an environment that may
lack the project's toolchain), this skill runs the **same checks** with one
addition.

### Toolchain preconditions (mode `code`)

The environment may lack the project's runtime, package manager, or network
access for dependencies. Before reviewing code, resolve the project's
lint / typecheck / test commands from `CLAUDE.md` and try them:

- If the commands **run** — even if they report failures — proceed with the
  review. Failures are review findings, not environment problems.
- If a command **cannot run at all** (interpreter or package manager
  missing, dependencies not installable, no network), **stop**. Output
  neither `APPROVE` nor `REQUEST CHANGES`. State exactly which command
  failed and which prerequisite is missing, then give the recovery options:
  provision this environment (install the runtime / dependencies), or run
  this review in a desktop session where the toolchain is available.
- "Toolchain absent" is a loud stop, never an implicit approval path —
  skipping the test gate silently would approve unverified code. This is
  the web/mobile elaboration of the "Never approve code without seeing test
  output" hard rule above.

### Comment precedence (both modes)

The *Comment precedence (anti-anchoring)* rule applies unchanged. Read the
full issue thread with `get_issue_comments` (author + body, chronological
order) and the PR review/issue comments via the server's PR-comments tool;
honor later accepted decisions over the original plan exactly as in the body.
Author, body, and timestamp are enough to order the thread and spot
`[decision]` / scope-extension comments — keep the field selection that
narrow. Reading **both** comment sources is also how you confirm the
`[decision]` breadcrumb is present on each surface **that exists**: if an
accepted decision is missing its breadcrumb on a surface that exists at review
time (always the issue; the PR once opened), request it before approving,
exactly as in the body.

Everything else in the body applies unchanged. An external reviewer is
reached the same way regardless of surface: assemble a `review-pack` packet
and hand it off.
