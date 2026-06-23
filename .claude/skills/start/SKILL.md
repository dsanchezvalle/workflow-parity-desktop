---
name: start
description: Orchestrate the implementation of an approved issue end-to-end — branch, plan-review, implement, code-review, verify, push. Works in both desktop (gh CLI) and web/mobile (git + GitHub MCP) sessions via capability detection. Use when the user says "start #N", "let's implement #N", or when the analyze plan has been approved.
---

# start

The orchestrator. Runs other skills in sequence, never skips a step.

> **One skill, two surfaces.** The body below is the desktop path
> (authenticated `gh` CLI). In a web/mobile session without `gh`,
> version-control operations (branch, commit, rebase, push) still use
> `git`; every GitHub API read/write goes through the GitHub MCP server.
> Read the body for *what* each step does, then apply the **MCP /
> web-session overrides** appendix at the end for *how*.
>
> **Capability detection.** If an authenticated `gh` is available, follow
> the body as written. If not, and a GitHub MCP server is connected, follow
> the appendix. If neither is available, stop and say so.

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
  maintainer on the issue — a durable, auditable decision record visible
  to any future reader of the thread. If it does not exist, stop and ask
  the human to post one.
- The working tree is clean (`git status` empty).
- The default branch is `develop`. Pull latest before branching.
- The remote is reachable (`git fetch origin` succeeds). If it fails, stop
  and report the exact error — do not implement work the session cannot
  push.

If any precondition fails, **stop** and tell the human exactly which one.

## Steps

1. **Move issue to In Progress.** Apply `status: in progress` and remove
   `status: ready`. If a Project v2 board is configured, also invoke the
   sidecar to mirror the move onto it:

   ```bash
   OWNER=$(gh repo view --json owner -q .owner.login)
   # Project number: prefer the committed .github/project.env, fall back to
   # the legacy PROJECT_NUMBER repo variable (pre-v1.11 installs).
   NUMBER=$(grep -E '^PROJECT_NUMBER=' .github/project.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
   NUMBER=${NUMBER:-$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")}
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
   Where `project-status-labeled.yml` is installed, applying the label also
   moves the board; the sidecar call stays as the desktop primary and the
   two are idempotent. Label names are exact — see `AGENTS.md` →
   `Required labels`.
2. **Branch** from `origin/develop`:
   - Type prefix from the issue's `type/*` label (or asked, if absent):
     one of `feat`, `fix`, `docs`, `refactor`, `chore`, `test`.
   - Slug: kebab-case of the issue title, max 6 words.
   - Branch name: `<type>/<issue>-<slug>`.
   - **Fail-fast push check**: run `git push --dry-run -u origin <branch>`
     now. A dry run contacts the remote without updating refs or triggering
     workflows. If it fails (auth, permissions), stop and report the exact
     error before any implementation work happens.
3. **Plan review** — invoke `code-review` in `plan` mode against the
   approved plan. If `REQUEST CHANGES`, post the review on the issue, stop.
4. **Implement** — write code in logical commits. Each commit:
   - is Conventional (`<type>(<scope>): <subject>`),
   - keeps the tree green (lint + typecheck pass),
   - is small enough to review on its own.
5. **Code review** — invoke `code-review` in `code` mode. If
   `REQUEST CHANGES`, fix in new commits and re-run. Do not amend reviewed
   commits. If `code-review` stops because the toolchain is unavailable in
   this environment (web/mobile), resolve that first — do not push
   unreviewed code.
6. **Sync check** — if any of `CLAUDE.md`, `AGENTS.md`, or
   `.github/workflows/` changed, run `verify-sync`. If it fails, stop.
7. **Rebase** onto `origin/develop`. Resolve any conflicts in the PR
   description, not silently.
8. **Push** the branch. The `auto-pr.yml` workflow opens the PR.

## Post-push

- **Confirm the PR was opened.** `auto-pr.yml` is the **sole** PR
  creator — do **not** run `gh pr create`. Poll `gh pr view <branch>`
  for up to 30s / 6 × 5s. If the PR is still absent after 30s, check
  whether an `auto-pr` workflow run is still pending:
  ```bash
  gh run list --workflow=auto-pr.yml --branch <branch> \
    --json status,conclusion \
    --jq '[.[] | select(.status == "in_progress" or .status == "queued")]'
  ```
  If a run is pending or just completed, wait up to another 30s. Only
  if polling times out **and** no `auto-pr` run is pending or succeeded,
  fall back to `gh pr create`. If the fallback returns a 422 / "A pull
  request already exists" error, treat it as success and re-fetch with
  `gh pr view <branch>`.
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
  `[decision] <what changed> — <why>.` comment on every surface that exists
  when the decision is taken — always the issue, and the PR once `auto-pr`
  opens it (a pre-push decision goes on the issue and is mirrored to the PR
  when it opens; never demanded before) — per AGENTS.md →
  Decision-breadcrumb convention.
- **Pre-merge freshness check.** The merge itself is the human's call and
  happens after `start` returns, but the freshness gate is part of this
  contract: **immediately before merging**, re-read the PR's current state —
  do not merge on the read you took at code-review time. An async reviewer (an
  external bot such as Codex, or a colleague) can land a comment *after*
  approval but *before* the merge; merging blind misses it.

  ```bash
  gh pr view <PR> --json reviews,comments,statusCheckRollup   # summaries + issue comments + checks
  gh api repos/<owner>/<repo>/pulls/<PR>/comments             # inline review-thread comments
  ```

  Both calls are needed: `gh pr view` does **not** return inline review
  comments (the line-anchored ones an async bot like Codex posts) — those come
  only from the `pulls/<PR>/comments` API, so reading just the first leaves the
  late feedback unseen. (MCP / web session: `get_pull_request_reviews` +
  `get_pull_request_comments` + `get_pull_request_status`.) If
  anything landed since the last review, judge it like any other review
  comment — never auto-apply, decline with a reason when a design decision
  forbids it — and address it in a new commit before merging, leaving a
  `[decision]` breadcrumb if it changes the trajectory. Reviewer-agnostic and
  cheap: two read calls. See AGENTS.md → Pre-merge freshness.

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
>   4. **If a Project v2 board is configured**, also move the issue back
>      to the `Ready` column — labels alone won't reset the board because
>      `project-status.yml` only handles merged PRs:
>      ```bash
>      OWNER=$(gh repo view --json owner -q .owner.login)
>      NUMBER=$(grep -E '^PROJECT_NUMBER=' .github/project.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
>      NUMBER=${NUMBER:-$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")}
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

The `code-review` skill says "Run them locally; paste output in the
PR" — that guidance assumed the PR body was the only durable verification
trail. In the GitHub-driven flow the `code-review` skill runs at **step 5,
before the push at step 8**, so no PR exists yet. Test output is in-session
context during the review step. Therefore:

- Run tests locally as required by `code-review`. Non-negotiable.
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
  `/code-review`, `/review-pack`, etc.).
- Status label values used as workflow references (e.g.,
  `status: ready`, `status: in progress`, `effort/E2`) — if a change's
  state is worth mentioning, describe it in plain language.
- Meta-commentary about the orchestration process ("as per the analyze
  plan", "skipping code-review for E0", etc.).
- Agent / tool attribution — `Co-Authored-By: Claude` (or any AI agent)
  trailers, `🤖 Generated with …` footers, or any mention of Claude,
  Codex, or the assistant that produced the change. Some tooling appends
  these automatically; strip them from commit messages, PR titles/bodies,
  and comments. The deliverable reads as the engineer's own work.

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

## MCP / web-session overrides

Apply this section **instead of** the `gh`/sidecar mechanics in the body
when you are in a web/mobile session without an authenticated `gh`. `git`
still owns version control; only the GitHub API mechanics differ. The
*what* of every step is unchanged.

### Tooling contract

- **Resolve tools by capability, not prefix.** The canonical GitHub MCP
  names used here (`get_issue`, `get_issue_comments`, `update_issue`,
  `list_pull_requests`, `get_pull_request`, `get_pull_request_reviews`,
  `get_pull_request_comments`, `get_pull_request_status`)
  may be exposed under a server-specific prefix — match by name suffix.
- **No GitHub MCP server connected → fail loud.** Stop and tell the human:
  connect the GitHub MCP integration, or run this issue in a desktop
  session where `gh` is available.
- **Field discipline (token efficiency).** Pick the narrowest tool; cap
  page sizes on list calls; extract only the fields each step needs. Never
  re-fetch an object already read this session. Never quote a full MCP
  payload into the conversation, a commit, or a PR body.

### Step overrides

- **Preconditions** — read the `status:*` / `effort/*` labels with
  `get_issue` (keep `labels[].name` only). Read the approval thread with
  `get_issue_comments` (author + body only) and confirm a maintainer
  `approved` comment exists. `git fetch origin` / `git push --dry-run`
  preconditions are git-native and run unchanged.
- **Step 1 (In Progress)** — apply `status: in progress` / remove
  `status: ready` with read-modify-write (most servers' `update_issue`
  replaces the full label set: take the names you already read, swap the
  two, write back; prefer dedicated add/remove-label tools if present). Do
  **not** invoke the sidecar and do **not** mutate the board from the
  session — `project-status-labeled.yml` moves the card from the label
  event, reading the number from `.github/project.env`.
- **Steps 2, 4, 6, 7, 8** — git-native (branch, commit, sync check,
  rebase, push), unchanged.
- **Steps 3 & 5 (reviews)** — invoke `code-review` (same skill); in
  `code` mode its toolchain preconditions apply (see that skill's
  MCP appendix).
- **Post-push: confirm the PR.** `auto-pr.yml` is still the sole creator —
  do **not** call `create_pull_request`. Poll `list_pull_requests`
  (state=open; keep `number`, `head.ref`, `state`) for up to 30s / 6 × 5s,
  matching the head branch **locally** by comparing `head.ref` to your
  branch — do not filter by `head: <owner>:<branch>`, since PRs opened by
  `github-actions[bot]` are not returned by that server-side filter. If the
  PR is still absent after 30s, check for a pending `auto-pr` run
  (`list_workflow_runs` for "Auto PR", `status: in_progress`/`queued`);
  wait up to another 30s. Only if polling times out **and** no run is
  pending/succeeded, fall back to `create_pull_request`; treat a 422
  "already exists" as success and re-fetch with `list_pull_requests`.
- **Post-push: confirm In Review.** Re-read labels with `get_issue` (keep
  `labels[].name`) and verify `status: in review` appears; if absent after
  30s, post a warning comment noting the label was not observed.
- **Post-push: fill the verification slot.** Read the PR body with
  `get_pull_request`, substitute the `<!-- start fills here -->`
  placeholder with the 1–3 line verification summary, and write it back
  with `update_pull_request`. If the placeholder is absent (older
  `auto-pr.yml`), append a fresh `## Verification` section instead.
- **Post-push: watch CI** via the PR's check results
  (`get_pull_request_status` or the server's check-runs tool — keep check
  names + conclusions only).
- **Pre-merge freshness** — re-read the PR immediately before merge:
  `get_pull_request_reviews` (review summaries), `get_pull_request_comments`
  (the inline review-thread comments — distinct from issue comments and the
  surface an async bot posts to), and `get_pull_request_status` (checks).
  Evaluate anything that landed since the last review. Same *what* as the
  body's *Pre-merge freshness check*; only the read mechanics differ.
- **Re-run cleanup** — close the open PR with `update_pull_request`
  (state `closed`) or the UI; delete the branch
  (`git branch -D <branch>` + `git push origin --delete <branch>`); swap
  labels back to `status: ready` with read-modify-write. The board
  move-back is automatic (re-applying `status: ready` triggers the labeled
  workflow). No manual board step, no sidecar.
- **Re-run remote-branch scan** — find an in-flight branch with
  `git ls-remote --heads origin | grep -E '/(feat|fix|docs|refactor|chore|test)/<issue>-'`
  (no MCP call needed); check for its open PR with `list_pull_requests`.
