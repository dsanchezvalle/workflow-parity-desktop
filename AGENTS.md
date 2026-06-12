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
                                                      └─► merge to develop
                                                            ├─► generate-changelog
                                                            ├─► clean-merged-branch
                                                            └─► project-status closes issue
                                                                  └─► later: release PR develop → main
                                                                        └─► back-merge main → develop
```

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
  - the issue has an approved plan comment (human reaction or "approved" comment),
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

Two modes. Hard split — the mode is required.

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

### deploy-pipeline

Stack-dependent. Filled from the template during setup.
Default checklist: build, lint, typecheck, env vars present, migrations
runnable & reversible, rollback plan documented.

### changelog-reporter

Trigger: push to `develop` (excluding `[skip ci]`).
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

## Invariants

- `start` never runs without an approved plan comment.
- `code-review (plan)` never runs without a plan in the issue.
- A skill never edits another skill's output.
- The setup conversation (`/workflow-setup`) is the only entry point that
  writes to `.workflow-staging/`.
