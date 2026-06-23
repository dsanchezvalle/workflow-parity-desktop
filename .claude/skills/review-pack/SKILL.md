<!-- CORE: agnostic -->
---
name: review-pack
description: "Generate a compact, neutral REVIEW CONTEXT PACKET for an external reviewer. Collects GitHub issue and PR metadata (title, body, acceptance criteria, scope, comments, decisions, changed files, checks, risks) via the GitHub MCP server or the gh CLI (whichever the session has) and formats it for pasting into another review tool. Use when the user wants to prepare a PR/issue review packet, share context with an external reviewer (e.g. Codex web), or summarize a GitHub PR and its linked issue. Never modifies files, posts comments, or pushes commits."
# Manual-only: this is a handoff tool the engineer/tech-lead invokes
# explicitly with /review-pack. The model must never auto-trigger it by
# relevance, and its description is not preloaded into context.
disable-model-invocation: true
---

# review-pack

Generates a compact, neutral **REVIEW CONTEXT PACKET** from GitHub issue and
PR metadata. The packet is formatted for pasting into another review tool.
It never modifies files, posts comments, or pushes commits.

First-class and shared across surfaces: this packet is the canonical,
reviewer-agnostic way to hand review context to **any** external reviewer.
The pack's own reviewer is the `code-review` skill (Claude); this packet is
for an additional external pass you run yourself, outside the workflow — the
pack neither invokes nor depends on a specific external tool. It is the
primary handoff path in web/mobile sessions (where local cross-review tools
aren't available) and works on desktop too.

---

## Step 1 — Gather inputs

Ask the user:

```
PR number? (e.g. 42)
Issue number? (e.g. 15 — or "none" if the PR has no linked issue)
```

Wait for the PR answer before proceeding. Do not infer or guess the PR number.

The issue number is **optional**. If the user answers `none` (or the PR links
no issue), render the packet in **PR-only mode**: omit the `Issue`,
`Issue intent`, `Acceptance criteria`, and `Scope / out of scope` sections, and
change the external-review prompt's first line to
`Review PR #<pr> in <owner/repo>.` (drop `against issue #<issue>`). Everything
else renders unchanged.

---

## Step 2 — Identify the repository

Detect owner and repo as the **last two path segments** of the current
working directory's `origin` remote — so it works regardless of host,
scheme, embedded auth, port, or proxy/path-style URL, not just `github.com`:

```bash
git remote get-url origin \
  | sed -E 's#/+$##; s#\.git$##; s#.*[/:]([^/:]+)/([^/]+)$#\1/\2#'
```

This yields `owner/repo` for every real remote form:

- HTTPS — `https://github.com/owner/repo.git`
- SSH (scp-style) — `git@github.com:owner/repo.git`
- auth-in-URL / explicit port — `https://user@host:443/owner/repo`
- proxy / path-style — `http://local_proxy@127.0.0.1/.../git/owner/repo`

Taking the final two segments (and matching the separator before `owner` as
either `/` or `:`) keeps the host/scheme/auth/port portion irrelevant. Strip
a trailing `.git` (and any trailing slash) first.

If the remote URL cannot be parsed into `owner/repo`, report the error and
stop. Do not ask the user to supply the repo name.

---

## Step 3 — Collect data

### Tooling: capability detection (GitHub MCP or `gh`)

All GitHub data comes from one source, resolved by capability:

- **Web/mobile session** — the connected GitHub MCP server (canonical tool
  names below: `get_issue`, `get_issue_comments`, `get_pull_request`, …;
  match by name suffix if the server prefixes them). This is the primary
  path for this skill.
- **Desktop session** — the authenticated `gh` CLI returns the same data
  points (`gh issue view --json`, `gh pr view --json`, `gh pr checks`).

Use whichever the session has; do not mix. If **neither** is available,
**fail loud**: stop and tell the user to connect the GitHub MCP integration
or authenticate `gh`, naming the data point you could not fetch. Never fall
back to scraping the public UI or guessing repo state.

Do not use non-GitHub sources.

### Field discipline (token efficiency)

Request the narrowest tool for each data point; cap page sizes; keep only
the fields listed below and drop the rest of each response. Never re-fetch
data already collected.

### Data to collect

#### Repository
- Owner/repo name (already resolved in Step 2)

#### Issue
- `get_issue` — keep title, body, labels, milestone.
- `get_issue_comments` (capped page size) — keep author + body; extract
  only: decisions, clarifications, scope changes, constraints, unresolved
  questions. Skip greetings, +1s, noise.

#### Pull request
- `get_pull_request` — keep title, body, state (open/merged/draft),
  mergeable status, base branch, head branch.
- Linked issue references: look for `#N`, `Closes #N`, `Fixes #N`,
  `Resolves #N` in the body you already have.
- `get_pull_request_files` — keep filenames only. Do NOT fetch patches or
  full diffs.
- PR timeline comments and review submissions
  (`get_pull_request_comments` / `get_pull_request_reviews`) — keep
  author, body, review state.
- Inline review comments (the per-line code comments) — keep path, line,
  body, author. Fetch these explicitly; servers that omit them from the
  timeline silently drop pending actionable feedback.

#### Checks / statuses

Fetch the PR's check results (`get_pull_request_status` or the server's
check-runs tool) — keep check names + conclusions only. Map the overall
state — do NOT flatten every non-passing state into `Not available`,
that hides legitimate states:

| Observed | Render in `Checks / status` |
|---|---|
| all checks concluded successfully | the check results (passing) |
| any check pending / queued / in progress | the partial results + `Pending` — never hide this |
| one or more failed | the failing checks |
| no checks reported at all | `Not available` |

Only the no-checks case renders `Not available`. Do NOT abort the packet
in any of these cases — but do NOT collapse `Pending` or a failure into
`Not available`, which would report a false state in the packet.

---

## Step 4 — Process and filter

### Issue processing
- Extract acceptance criteria: look for checkbox lists (`- [ ]`, `- [x]`),
  numbered lists under headings like "Acceptance criteria", "Definition of
  done", "Requirements", "Must", "Should".
- Extract scope / out-of-scope: look for headings or bullet points containing
  "scope", "out of scope", "not included", "excluded", "won't".
- Issue intent: 1–2 sentence neutral summary of what the issue is asking for.

### PR processing
- PR intent: 1–2 sentence neutral summary of what the PR implements.
- Implementation summary: derive from PR description, not diff content. What
  does the author say was changed and why?
- Changed files: use the filename-only list. For each file, infer a short
  purpose (1 phrase) from the filename and path only — do not read file
  contents.

### Comment filtering rules
From all issue comments, PR comments, review comments, and review
submissions, keep only:
- Explicit decisions ("we decided to…", "agreed that…", "won't do X because…")
- Clarifications that change scope or requirements
- Unresolved questions or blockers
- Accepted or explicitly rejected trade-offs
- Actionable review feedback (not yet resolved)

Discard: greetings, LGTM, auto-generated status updates, CI bot summaries.

### Anti-circularity rule for prior review comments
If prior automated review comments exist (from bots, CI tools, code-review
tools, or any automated agent):
- Do NOT name the tool or bot.
- Do NOT present their findings as confirmed truth.
- Include them ONLY under `Prior review signals to verify independently`.
- Phrase as: `Potential concern raised in prior review: <neutral description>`
- Never write "confirmed by", "bot says", "tool found", or similar.

### Risks
Derive from:
- PR description warnings, TODOs, or known issues
- Unresolved review comments
- File paths that touch auth, permissions, migrations, CI config, state
  management, versioning, or public APIs
- Draft/non-mergeable status

### Suggested external review focus
Based on the accepted criteria, changed files, and risks. Be specific to
this PR — do not emit generic advice.

---

## Step 5 — Render packet

Output **exactly** this format. No prose before or after it. No markdown code
fences wrapping the whole output (the internal `text` block below is
intentional for the prompt section only).

In **PR-only mode** (no issue supplied, see Step 1), omit the `Issue`,
`Issue intent`, `Acceptance criteria`, and `Scope / out of scope` sections, and
render the external-review prompt's first line as `Review PR #<pr> in
<owner/repo>.` (without `against issue #<issue>`).

```
REVIEW CONTEXT PACKET

Repo:
<owner/repo>

Issue:
#<issue> — <title>

Issue intent:
<1–2 sentences>

Acceptance criteria:
- <max 6 bullets>

Scope / out of scope:
- <max 4 bullets>

PR:
#<pr> — <title>

PR intent:
<1–2 sentences>

Implementation summary:
- <max 6 bullets>

Changed files:
- <path>: <purpose>
- <path>: <purpose>

Important decisions / clarifications:
- <max 6 bullets from issue/PR/comments>

Prior review signals to verify independently:
- <max 5 bullets, only if prior review comments exist; otherwise "None identified">

Known risks / trade-offs:
- <max 6 bullets>

Checks / status:
- <check/status>: <result>

Suggested external review focus:
- <max 6 bullets>

External review prompt:
Review PR #<pr> in <owner/repo> against issue #<issue>.

Use the checked-out branch/diff as the source of truth for code changes. Use the REVIEW CONTEXT PACKET above only as GitHub issue/PR metadata. Do not modify files. Do not push commits.

Focus adversarially on whether the PR satisfies the issue, whether the implementation introduces regressions, whether docs match behavior, whether edge cases are handled, and whether any workflow, migration, versioning, permissions, auth, CI, or state-management assumptions are unsafe.

Return:
1. Verdict
2. Blockers/P1
3. High/Medium risks
4. Low/polish
5. Checks run
6. What this review may have missed
─────────────────────────────────────────────────────────────
If your external reviewer runs in a sandboxed cloud env (e.g. Codex web):
1. Ensure the environment has Internet access enabled.
2. Paste this into its allowlist field (otherwise the reviewer
   can only scrape GitHub's public UI — no git fetch, no diff):

github.com, raw.githubusercontent.com, api.github.com
─────────────────────────────────────────────────────────────
```

---

## Token-efficiency rules

- Prefer summaries over quotes.
- Do not include full comment threads.
- Do not include full diffs or file contents.
- Do not repeat the same decision across sections.
- Cap sections as specified (3–6 bullets max per section).
- Preserve exact names of files, commands, fields, flags, and acceptance
  criteria.
- If a section has no useful information, write `None identified`.

---

## Guardrails

This skill must NEVER:
1. Modify any file in the repository.
2. Push commits or create branches.
3. Post comments or reviews to GitHub.
4. Include secrets, tokens, or local absolute paths in the output.
5. Include full file diffs in the output.
6. Name bots or automated tools as authoritative sources.
7. Access non-GitHub sources (no web search, no docs sites, no internal wikis).
8. Read local project files beyond what is needed to identify owner/repo and
   branch.
