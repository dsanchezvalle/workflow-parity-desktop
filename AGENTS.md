<!-- CORE: agnostic -->
# AGENTS.md — Flow & skill specifications

This file defines the issue-driven workflow and the contract each skill must
honor. It is **agnostic**: no stack, framework, or domain assumptions live
here. Project-specific details live in [CLAUDE.md](CLAUDE.md), filled from the
setup `context.yml`.

## End-to-end flow

```
issue (Backlog)
  └─► analyze
        └─► plan posted on issue, label `effort/E{n}` applied
              └─► human approves on the issue
                    └─► start
                          ├─► move issue to In Progress
                          ├─► create branch <type>/<issue>-<slug>
                          ├─► code-review (mode=plan)
                          ├─► implement
                          ├─► code-review (mode=code)
                          ├─► verify-sync (if docs or workflows touched)
                          ├─► rebase onto develop
                          └─► push  ──► auto-pr workflow opens PR
                                          └─► project-status moves to In Review
                                                └─► CI green + human approval
                                                      └─► pre-merge freshness check (re-read PR reviews/comments)
                                                            └─► merge to develop
                                                                  ├─► generate-changelog
                                                                  ├─► clean-merged-branch
                                                                  └─► project-status closes issue
                                                                        └─► later: release PR develop → main
                                                                              └─► back-merge main → develop
```

## Flow availability matrix

**Single source of truth for what exists when.** Rows are flow milestones;
columns are the artifacts/surfaces a step might depend on; a cell says whether
that artifact exists *at the end of* that milestone. A step must never assume an
input that the matrix shows as `—` at its row.

| After milestone | issue | branch | commits | PR | CI | board\* |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| analyze (plan posted) | ✓ | — | — | — | — | ✓\* |
| start: branch created | ✓ | ✓ | — | — | — | ✓\* |
| code-review (plan) | ✓ | ✓ | — | **—** | — | ✓\* |
| implement (commits) | ✓ | ✓ | ✓ | — | — | ✓\* |
| code-review (code) | ✓ | ✓ | ✓ | **—** | — | ✓\* |
| push → auto-pr | ✓ | ✓ | ✓ | **✓** | ✓ | ✓\* |
| merge to develop | ✓ | deleted | ✓ (in develop) | merged | ✓ | ✓\* (done) |

\* **`board` is configuration-conditional.** The Project v2 **card** exists
only when Project v2 is configured (`.github/project.env`, or the legacy
`PROJECT_NUMBER` variable). Read every `board` cell as "✓ **if configured**,
else **labels-only**": with no project number the flow runs labels-only and
**no card exists** — the always-applied `status:*` labels (see *Required
labels*) carry the signal instead. So an instruction must not assume a board
card exists; the issue and its `status:*` label are the unconditional carriers.
This is the first config-conditional column the *Extensibility* note below
anticipates.

The `PR = —` cells on both **code-review** rows are load-bearing: `code-review`
runs pre-push (start steps 3 and 5), so the PR does not exist yet — it is born
at the push (start step 8). A rule that demands a `[decision]` breadcrumb *on
the PR* during `code-review` is unsatisfiable by construction; the breadcrumb is
required only on surfaces that exist at review time (always the issue; the PR
once `auto-pr` opens it). This failure mode is prevented by reading the matrix.

**Derived rule.** No instruction may assume an artifact its step does not
guarantee — check this matrix before requiring an input. Preconditions in the
skill specs below are validated against it.

**Pre-merge freshness.** A precondition of the **merge** row: before
merging, re-read the PR's current state — its reviews, comments, and check
rollup. They exist (PR opened at push) and **may have changed since the last
`code-review`**: an asynchronous reviewer (an external bot such as Codex, or a
colleague) can land a comment *after* the decision to approve but *before* the
merge lands, and that window is invisible to anyone who merges on a stale read.
Reviewer-agnostic and cheap — two read calls:

```bash
gh pr view <N> --json reviews,comments,statusCheckRollup   # review summaries, issue comments, checks
gh api repos/<owner>/<repo>/pulls/<N>/comments             # inline review-thread comments
# MCP equivalent: get_pull_request_reviews + get_pull_request_comments + get_pull_request_status
```

Both reads are required: `gh pr view` returns issue-level comments and each
review's *summary* body, but **not** the inline comments attached to specific
lines — those live only in the review-comments API (`pulls/<N>/comments`). An
async bot like Codex posts its findings as inline review comments, so omitting
that second call re-reads the PR yet still misses exactly the late feedback this
check exists to catch.

If anything landed since the last review, **evaluate it before merging** — judge
it like any other review comment (see `code-review` → *External reviewer bot*);
do not merge blind. If it warrants a trajectory change, leave a `[decision]`
breadcrumb (see *Decision-breadcrumb convention*) and address it in a new commit
rather than merging over it. This precondition is owned by whoever performs the
merge; `start` restates it at its close (the *Pre-merge freshness check* in its
*Post-push* section).

**Trajectory decisions change what exists.** The flow is near-linear, but the
*decisions* taken along it (a mid-implementation pivot, a re-scope, a
`/resume` into a fresh session) determine which step comes next and therefore
which inputs are present. Consult the matrix for the **actual** next step, not
the nominal one — a resumed issue at `status: ready` may carry only a branch and
no commits, for example.

**Extensibility (door left open).** Today the matrix models one path. It extends
to alternative routes without rewrite: add rows, or make a cell's availability
conditional on the route taken — the `board\*` column already does exactly this
(conditional on Project v2 configuration). Multi-route modelling is out of scope
now but the shape (rows = milestones, columns = surfaces, cell = exists-or-not,
optionally conditional) does not preclude it.

**Modality note.** This matrix is the **github-driven** flow. The `local`
modality produces no GitHub PR or CI surfaces — its trajectory decisions and
breadcrumbs live in the workspace JSON, not on a PR (see
[local/README.md](../../local/README.md) → *End-to-end flow* / *Decision
breadcrumbs*). The temporal axis (*what exists when*) modelled here is distinct
from the cross-pack axis (*what file lives in which modality*) tracked
separately; both touch this file but do not share cells.

**Maintenance note.** When you add or reorder a step, or change what a step
produces, **revalidate this matrix in the same change**. It is the single
source: skill specs reference it ("see AGENTS.md → Flow availability matrix"),
they do not restate it.

## Skill specs

All skills are project-agnostic by definition. Project-specific behavior is
parameterized via `CLAUDE.md` placeholders or read at runtime from the repo.

### analyze

Inputs: issue number or URL.
Outputs: a comment on the issue containing
  1. one-line restatement of the request,
  2. effort classification (E0–E3) with the reason,
  3. a plan sized to the effort,
  4. open questions for the human, if any.
Side-effects: applies `effort/E{n}` label.
Constraints: must not create a branch, must not write code.

### start

Inputs: issue number, link to the approved plan comment.
Preconditions:
  - the issue has an approved plan comment (a comment containing the literal
    word "approved" from a maintainer — the only valid approval signal),
  - working tree is clean,
  - default branch is `develop`.
Steps:
  1. Move issue to In Progress.
  2. Create branch from `develop`: `<type>/<issue>-<slug>`.
  3. Run `code-review` in `plan` mode against the approved plan.
  4. Implement, committing logically (Conventional Commits).
  5. Run `code-review` in `code` mode.
  6. Run `verify-sync` if docs or workflows changed.
  7. Rebase onto `origin/develop`.
  8. Push. The `auto-pr` workflow opens the PR.
Postconditions: PR exists, linked to issue, CI running.

### code-review

Two modes. Hard split — the mode is required. Both run pre-push, so the PR does
not exist yet (see *Flow availability matrix*): never require an artifact the
matrix marks `—` at the code-review rows.

**Mode `plan`** — runs before any code is written.
Checks:
  - architectural fit with existing code,
  - anti-overengineering (no speculative abstractions, no premature generalization),
  - scope discipline (does the plan match the issue?),
  - missing test or rollback considerations.
Output: APPROVE / REQUEST CHANGES, with line items.

**Mode `code`** — runs after implementation, before push.
Checks:
  - implementation matches the approved plan,
  - security (input validation at boundaries, secrets, authz),
  - performance (no obvious N+1, unbounded loops, sync I/O in hot paths),
  - Conventional Commit messages,
  - tests cover the change (unit at minimum; integration if I/O involved).
Output: APPROVE / REQUEST CHANGES, with line items.

An optional **external reviewer bot** (e.g. Codex commenting on the PR,
automatically or via `@codex review`) is treated as an **independent
reviewer**, never an auto-apply queue: judge each comment with full context,
never auto-apply, and decline any — with a reason — when a design decision
forbids it or it is not pertinent. The pack neither installs nor requires it
(reviewer-agnostic). See `code-review` → *External reviewer bot*.

### review-pack

Inputs: PR number (required), linked issue number (optional).
Outputs: a neutral REVIEW CONTEXT PACKET (issue/PR intent, acceptance
criteria, scope, decisions, changed files, checks, risks) formatted for
handoff to an external reviewer. Read-only — never modifies files, posts
comments, or pushes.
Tooling: capability-detected — GitHub MCP (web/mobile) or `gh` (desktop).
Use: an optional external review pass the engineer runs; the pack's own
reviewer is `code-review`, and the pack stays reviewer-agnostic.

### deploy-pipeline

Stack-dependent. Filled from the template during setup.
Default checklist: build, lint, typecheck, env vars present, migrations
runnable & reversible, rollback plan documented.

### changelog-reporter

Trigger: push to `develop` (skips its own `chore(changelog): update` commits
by subject — not `[skip ci]`, which would poison the release boundary).
Behavior: appends a date-grouped entry to `CHANGELOG.md` derived from the
merged commits since the last entry. **No version numbers.** Format:

```
## YYYY-MM-DD
- <type>: <subject> (#<issue>)
```

### verify-sync

Bidirectional structural check between `CLAUDE.md` / `AGENTS.md` and
`.github/workflows/`. Examples:
  - every skill listed in CLAUDE.md exists at the referenced path,
  - every workflow file is referenced or explicitly listed in CLAUDE.md,
  - the branching model in CLAUDE.md matches workflow triggers.
Output: PASS / FAIL with diffable details.

## Repository workflows

The setup installs these GitHub Actions workflows under
`.github/workflows/`. The skill-driven flow above depends on them; they
are listed here by filename so `check-docs-sync` can verify each is
documented (the check greps `AGENTS.md` for every `*.yml` basename).

- `ci` — runs the project's lint, typecheck, and test commands on every
  PR to `develop` and on push to `develop` / `main`.
- `auto-pr` — opens a PR to `develop` when a feature branch is pushed,
  linking it to the originating issue via `Closes #N`.
- `project-status` — fires on PR open / merge events and updates the
  linked issue's `status:*` label and Project v2 Status field.
- `project-status-labeled` — server-side Project v2 board sync. Listens to
  `issues: labeled` and PR open/merge events and moves the board card to the
  matching column, reading the number from `.github/project.env` (falling
  back to the legacy `PROJECT_NUMBER` variable). Keeps the board in sync for
  web/mobile sessions with no session-side sidecar, and is idempotent with
  the `project-status-set.sh` sidecar the desktop skills call.
- `issue-status-default` — applies `status: backlog` to newly opened
  issues so every issue starts from a known state.
- `generate-changelog` — appends a date-grouped entry to `CHANGELOG.md`
  on push to `develop`.
- `clean-merged-branch` — deletes the feature branch after squash-merge.
- `back-merge` — opens a back-merge PR from `main` into `develop` after
  a release so `develop` never falls behind.
- `check-docs-sync` — CI-time enforcement of the `verify-sync` skill:
  every skill in `CLAUDE.md` resolves, every workflow file appears in
  `AGENTS.md`, and any workflow change is co-changed with `CLAUDE.md`
  or `AGENTS.md`.
- `validate-release-pr` — gates PRs from `develop` to `main` (release
  shape: Conventional Commit title, no merge commits, base is `main`).

## Escalation rules

- Any change touching authentication, billing, data migration, public API
  shape, or paths listed under `` in CLAUDE.md → E3.
- Any plan rejected twice by `code-review (plan)` → escalate to human.
- Any failed `verify-sync` → block push; do not proceed.

## Required labels

The setup script creates this exact set via `gh label create`. Skills and
workflows assert these names verbatim — a typo means the workflow fails
loudly so the readiness check catches it.

**Effort** (applied by `analyze`):

- `effort/E0`, `effort/E1`, `effort/E2`, `effort/E3`

**Status** (applied by `analyze` / `start` / `project-status.yml`):

- `status: backlog` — `issue-status-default.yml` applies on issue
  opened. Default state for newly opened issues, no human action needed.
- `status: ready` — `analyze` applies after posting the plan, awaiting
  human approval (replaces `status: backlog`).
- `status: in progress` — `start` applies on branch creation.
- `status: in review` — `project-status.yml` applies on PR open.
- `status: done` — `project-status.yml` applies on PR merged.

**Type** (applied by humans on issue creation; `start` reads it to pick the
branch prefix):

- `type/feat`, `type/fix`, `type/docs`, `type/refactor`, `type/chore`, `type/test`

Notes:

- Project v2 board (opt-in): if `vars.PROJECT_NUMBER` is set, the board
  carries the primary signal; the `status:*` labels remain as a secondary
  signal so label-only consumers stay correct.
- All label mutations in `project-status.yml` run **without** `|| true` —
  if a label is missing or misnamed, the workflow fails. Do not silence it.

## Decision-breadcrumb convention

The issue carries the original intent (analyze plan, status labels).
The PR, **once it exists**, carries the diff and its review comments. Any
**decision that changes the trajectory after the plan was approved** must
leave a concise breadcrumb so a future reader can reconstruct *why* the
implementation ended where it did without opening the chat.

**Trigger events** (any of) — a trajectory-changing decision is:

- A pre-push `code-review` (plan or code mode) iteration that returned
  `REQUEST CHANGES` and was acted on.
- A technical pivot mid-implementation (chosen approach abandoned for
  a different one).
- A business or technical clarification — **including one surfaced during
  PR review** (by the engineer, the tech-lead, or an external reviewer such
  as Codex) — that changes acceptance criteria. Example: a requirement stated
  in the issue is found, on review, to be unnecessary after a technical or
  business change and is dropped; that decision steers every adjustment made
  after it.
- A scope adjustment (item dropped, item added) relative to the
  approved plan.

**Where to post — every surface that exists when the decision is taken.**
The required surfaces follow the *Flow availability matrix*, not a fixed
"both": the **issue always exists**; the **PR exists only once `auto-pr`
opens it** (`start` step 8). Never demand a breadcrumb on a surface the
matrix marks `—` at that point. Two cases:

- **Pre-push decision** — taken during `analyze`, `start`, or a pre-push
  `code-review` plan/code pass, when the PR does not exist yet. Post the
  breadcrumb on the **issue** (the canonical record). When `auto-pr` later
  opens the PR, `start` **mirrors** the same `[decision]` text onto the PR so
  a PR-only reader sees it — mirrored once the PR exists, never demanded
  before.
- **PR-review decision** — taken after the PR is open, during review by the
  engineer / tech-lead / external reviewer, or in any later session. Both the
  issue and the PR exist, so post the same text on **both**. This is the
  bucket the "both surfaces" expectation was always about — note that the
  pre-push `code-review` *skill* is a distinct step from this post-open PR
  review; do not conflate them.

**Format** — one or two lines, same text on each surface it is posted to:

```
[decision] <what changed> — <why>.
```

Example:

```
[decision] Switched from in-process queue to Redis Streams — review
flagged that the in-process queue loses messages on pod restart.
```

The executing skill (`start`, `code-review`) posts the comment on the
surface(s) that exist when it detects a trigger event. The engineer may
append a follow-up comment with deeper rationale when the one-liner is
insufficient.

These breadcrumbs are **consumed**, not write-only: `code-review` honors them
on re-review via its *Comment precedence (anti-anchoring)* rule — a later
`[decision]` recording an accepted scope change is respected, not re-flagged
as a plan deviation on the next pass.

## Invariants

- `start` never runs without an approved plan comment.
- `code-review (plan)` never runs without a plan in the issue.
- A skill never edits another skill's output.
- The setup conversation (`/workflow-setup`) is the only entry point that
  writes to `.workflow-staging/`.
- Any trigger event listed under **Decision-breadcrumb convention**
  must leave a matching breadcrumb on every surface that exists when the
  decision is taken — always the issue; the PR once `auto-pr` opens it
  (per the **Flow availability matrix**), never demanded before.
- No instruction assumes an artifact its step does not guarantee —
  validated against the **Flow availability matrix** (the single source for
  *what exists when*).
- A PR is never merged on a stale read: its reviews/comments/checks are
  re-read immediately before the merge (see **Pre-merge freshness**), so an
  asynchronous review landing between approval and merge is evaluated, not
  missed.
