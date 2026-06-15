<!-- CORE: agnostic -->
---
name: start
description: Orchestrate the implementation of an approved issue end-to-end — branch, plan-review, implement, code-review, verify, push. Use when the user says "start #N", "let's implement #N", or when the analyze plan has been approved.
---

# start

The orchestrator. Runs other skills in sequence, never skips a step.

## Preconditions

- The issue must have **either** a `status: ready` label **or** an
  `effort/E0`–`effort/E3` label applied. If both are absent the issue
  has not been triaged. Refuse and tell the human:

  > This issue has not been triaged. Run `/analyze #N` first to
  > classify effort and post a plan; then re-run `/start #N`.

  Rationale: skipping `/analyze` means there is no plan to review,
  which makes `code-review (plan)` operate on nothing and breaks the
  audit trail.
- The issue has an **approved plan** comment. The **only** valid approval
  signal is a comment containing the literal word `approved` from a
  maintainer. Reactions (thumbs-up etc.) are **not** accepted: they are
  easy to mis-click, easy to miss in audit, and not visible as a durable
  decision record. This matches the mobile pack's stricter form and the
  maintainer's operational convention.
- The working tree is clean (`git status` empty).
- The default branch is `develop`. Pull latest before branching.

If any precondition fails, **stop** and tell the human exactly which one.

## Steps

1. **Move issue to In Progress.** Apply `status: in progress` and remove
   `status: ready`. If the repo variable `PROJECT_NUMBER` is set, also
   invoke the sidecar to mirror the move onto the Project v2 board:

   ```bash
   OWNER=$(gh repo view --json owner -q .owner.login)
   NUMBER=$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")
   if [ -n "$NUMBER" ]; then
     OWNER="$OWNER" NUMBER="$NUMBER" \
     REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
     ISSUE="<this-issue-number>" STATUS="In Progress" \
       bash .github/scripts/project-status-set.sh
   fi
   ```

   `project-status.yml` does **not** handle this transition — it runs on
   PR events, and at this point in the flow there is no PR yet. The
   workflow takes over for `In Review` (PR open) and `Done` (PR merged).
   Label names are exact — see `AGENTS.md` → `Required labels`.
2. **Branch** from `origin/develop`:
   - Type prefix from the issue's `type/*` label (or asked, if absent):
     one of `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.
   - Slug: kebab-case of the issue title, max 6 words.
   - Branch name: `<type>/<issue>-<slug>`.
3. **Plan review** — invoke `code-review` in `plan` mode against the
   approved plan. If `REQUEST CHANGES`, post the review on the issue, stop.
4. **Implement** — write code in logical commits. Each commit:
   - is Conventional (`<type>(<scope>): <subject>`),
   - keeps the tree green (lint + typecheck pass),
   - is small enough to review on its own.
5. **Code review** — invoke `code-review` in `code` mode. If
   `REQUEST CHANGES`, fix in new commits and re-run. Do not amend reviewed
   commits.
6. **Sync check** — if any of `CLAUDE.md`, `AGENTS.md`, or
   `.github/workflows/` changed, run `verify-sync`. If it fails, stop.
7. **Rebase** onto `origin/develop`. Resolve any conflicts in the PR
   description, not silently.
8. **Push** the branch. The `auto-pr.yml` workflow opens the PR.

## Post-push

- Confirm the PR was opened (poll `gh pr view <branch>` for up to 30s).
- Confirm `project-status.yml` moved the issue to In Review.
- **Fill the verification slot in the PR body.** `auto-pr.yml` opens
  the PR with a `## Verification` section containing the placeholder
  `<!-- start fills here -->`. Replace it with the 1–3 line
  verification summary required by the start contract:

  ```bash
  PR=<pr-number>
  SUMMARY="<1-3 lines: build pass, tests, what was visually checked>"
  CURRENT=$(gh pr view "$PR" --json body --jq .body)
  NEW=${CURRENT/<!-- start fills here -->/$SUMMARY}
  gh pr edit "$PR" --body "$NEW"
  ```

  If the placeholder is absent (e.g. consumer pinned an older
  `auto-pr.yml`), append a fresh `## Verification` section with the
  same summary text instead of editing the placeholder.
- Watch CI; if a check fails, fix it before tagging a reviewer.
- **Decision breadcrumbs.** If during the implementation you pivoted
  technically, dropped or added scope versus the approved plan, or
  acted on a `code-review` `REQUEST CHANGES` iteration, post a
  `[decision] <what changed> — <why>.` comment on **both** the issue
  and the PR (same text on both surfaces) per AGENTS.md →
  Decision-breadcrumb convention.

## Re-run policy

Before doing any work, **check whether this issue already has start
artifacts in flight**:

- A branch on the remote matching `<type>/<issue>-*` for this issue
  number (any type prefix).
- An open PR linked to this issue (head ref matches the same pattern,
  or PR body contains `Closes #<issue>`).
- A `status: in progress` or `status: in review` label.

If **any** of those exists, refuse loud. A silent re-run would diverge
the in-session work from the canonical surfaces (branch, PR, labels),
which is fail-silent and harder to recover from than a clean re-do.

Stop and reply:

> Issue #N already has a `/start` branch / PR / status label in
> flight. Silently re-running would diverge what I produce in this
> session from what the issue and remote record.
>
> If you want to redo the implementation, clean the canonical state
> first:
>
>   1. Close the open PR (if any). **Note**: closing a PR without
>      merging does NOT trigger `project-status.yml`'s move-back —
>      it only runs on merged PRs. So the next step is required even
>      when there is no PR yet.
>   2. Delete the existing branch locally and on the remote
>      (`git branch -D <branch>` + `git push origin :<branch>`).
>   3. Move the issue back to `status: ready` — remove the in-flight
>      labels and add `status: ready` back. Per the repo's contract
>      (AGENTS.md → Required labels), every open issue must carry a
>      status label:
>      ```bash
>      gh issue edit <issue-number> \
>        --remove-label "status: in progress" \
>        --remove-label "status: in review" \
>        --add-label "status: ready"
>      ```
>   4. **If this repo has `PROJECT_NUMBER` set** (Project v2 board
>      installed), also move the issue back to the `Ready` column —
>      labels alone won't reset the board because
>      `project-status.yml` only handles merged PRs:
>      ```bash
>      OWNER=$(gh repo view --json owner -q .owner.login)
>      NUMBER=$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")
>      if [ -n "$NUMBER" ]; then
>        OWNER="$OWNER" NUMBER="$NUMBER" \
>          REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
>          ISSUE="<this-issue-number>" STATUS="Ready" \
>          bash .github/scripts/project-status-set.sh
>      fi
>      ```
>   5. Re-run `/start #N`.
>
> If you only want to add more commits to the existing branch, do
> that directly — don't re-invoke `/start`.

The engineer or tech-lead owns the cleanup decision; the skill never
auto-deletes branches or PRs.

## External output style (commits + PR body)

The rich context lives **internally** — issue comments, analyze plans, and
code-review comments are all on the GitHub issue and PR (accessible to
authorized contributors but separate from the deliverable itself).
Externally-visible artifacts (commit messages, PR title/body, documentation
produced as the issue's deliverable) must be concise and must not reference
the workflow's internal machinery. Their audience is collaborators reviewing
the diff, not the orchestration process that produced it.

### Commit messages

- **Subject**: Conventional Commits (`<type>(<scope>): <subject>`),
  max 72 chars. Imperative mood.
- **Body**: optional. Only if it adds info the subject cannot capture
  (rollback hint, breaking change marker, security implication). Max ~3
  lines. **Never copy the analyze plan into the commit body.**

If a commit's body would be more than 3 lines of summary, that's a signal
to split the work into multiple commits, not to fatten the message.

### PR body

Suggested skeleton:

```
<1-2 sentences: what changed + why>

## Changes
- <bullet 1>
- <bullet 2>
- ... (5–8 bullets, up to ~10 if strictly needed, file/area/concept level)

## Verification
<1-3 lines: build pass, tests, what was visually checked>

Closes #<issue-number>
```

Do **not** dump the issue body, the analyze plan, full file inventories,
or "out of scope" lists into the PR description. The analyze plan lives on
the GitHub issue; collaborators who land on the PR don't need it to
understand the change.

Target: ~25 lines total across all commit bodies + PR body combined for any
single issue (~30 if the change is genuinely complex). If the engineer feels
the work needs more context to be reviewable, the issue should probably be
split into smaller pieces.

### Override: test output in the PR body

The `code-review.md` skill says "Run them locally; paste output in the
PR" — that guidance assumed the PR body was the only durable verification
trail. In the GitHub-driven flow the `code-review` skill runs at **step 5,
before the push at step 8**, so no PR exists yet. Test output is in-session
context during the review step. Therefore:

- Run tests locally as required by `code-review.md`. Non-negotiable.
- In the PR body, summarize the verification in 1-3 lines — e.g.
  `unit + integration green locally; lint + typecheck pass`. Do **not**
  paste raw test output, coverage tables, or terminal dumps into the PR
  body.
- If reviewers need the full output, post it as a **PR comment** after the
  PR opens — not in the body.

### Anti-leak rule (no workflow references in external artifacts)

External-facing artifacts must not reference the workflow's internal
machinery. Collaborators reviewing the diff should see clean, conventional
commit messages and PR bodies — not the orchestration scaffolding that
produced them.

**Forbidden in any external artifact**:
- Skill names invoked during the workflow (`/analyze`, `/start`,
  `/code-review`, etc.).
- Status label values used as workflow references (e.g.,
  `status: ready`, `status: in progress`, `effort/E2`) — if a change's
  state is worth mentioning, describe it in plain language.
- Meta-commentary about the orchestration process ("as per the analyze
  plan", "skipping code-review for E0", etc.).

**Does not apply to**:
- `Closes #N` in PR bodies — this is the standard GitHub convention for
  linking a PR to its issue and should be used.
- Any repo whose subject **is** this workflow itself (e.g.
  `workflow-template`, forks, or repos whose docs legitimately describe
  the workflow). In those repos, naming skill names is required in the
  appropriate files. Apply judgment: if a commit edits a skill spec,
  mentioning `/start` is required; if it lands an unrelated feature, the
  anti-leak rule still applies to that feature's commit and PR body.

**Applies to**:
- Commit subjects and bodies.
- Branch names.
- PR titles and descriptions.
- Documentation, guides, READMEs, runbooks produced as part of the
  issue deliverable.
- Any other artifact visible to collaborators in the remote (release
  notes, replies on PR comments, etc.).

## Hard rules

- Never push to `develop` or `main` directly.
- Never use `--force` or `--no-verify`.
- Never skip `code-review (plan)` — even for E0 changes inside `start`.
- If `start` is invoked on an issue without an approved plan, refuse and
  point the human at `analyze`.
- Never re-run silently when start artifacts (branch / PR / in-flight
  status) already exist for the issue. See "Re-run policy" above.
- Never copy the issue body, analyze plan, or code-review comments
  verbatim into commit messages or PR body. External outputs are concise
  per the "External output style" section above.
- Never reference workflow internals (skill names, status labels, workflow
  process meta-commentary) in any external artifact — commits, branch
  names, PR title/body, or documentation produced as part of the
  deliverable. See the "Anti-leak rule" section under External output
  style.
