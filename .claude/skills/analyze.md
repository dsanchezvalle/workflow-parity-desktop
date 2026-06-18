<!-- CORE: agnostic -->
---
name: analyze
description: Triage a GitHub issue, classify it E0–E3, and post a sized plan as a comment. Works in both desktop (gh CLI) and web/mobile (GitHub MCP) sessions via capability detection. Use when the user says "analyze #N", "triage this issue", or pastes an issue URL and asks how to approach it.
---

# analyze

Read the issue, decide effort, post a plan. Do **not** create branches or
write code.

> **One skill, two surfaces.** The body below is the desktop path
> (authenticated `gh` CLI). In a web/mobile session without `gh`, read the
> body for *what* each step does, then apply the **MCP / web-session
> overrides** appendix at the end for *how* to do it — same labels, same
> artifacts, same board outcome.
>
> **Capability detection.** If an authenticated `gh` is available, follow
> the body as written. If not, and a GitHub MCP server is connected, follow
> the appendix. If neither is available, stop and say so.

## Inputs

- Issue number or URL (required).
- Repo context: `CLAUDE.md`, `AGENTS.md`, recent commits if relevant.

## Output (one issue comment)

1. **Restatement** — one sentence in your own words.
2. **Effort** — `E0`, `E1`, `E2`, or `E3`, with a one-line reason.
3. **Plan** — sized per effort, see below.
4. **Open questions** — bullets, if any. Empty section if none.

Apply two labels:

- `effort/E0`, `effort/E1`, `effort/E2`, or `effort/E3` (one of).
- `status: ready` — signals "plan posted, awaiting human approval".

Both names must match exactly; the setup creates them verbatim.

If a Project v2 board is configured, also mirror the move onto it. **First
ensure the issue is already a board item** — `project-status-set.sh` updates
the Status field but does not add the issue if it is absent. Add it
explicitly before calling the sidecar:

```bash
OWNER=$(gh repo view --json owner -q .owner.login)
# Project number: prefer the committed .github/project.env, fall back to
# the legacy PROJECT_NUMBER repo variable (pre-v1.11 installs).
NUMBER=$(grep -E '^PROJECT_NUMBER=' .github/project.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
NUMBER=${NUMBER:-$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")}
if [ -n "$NUMBER" ]; then
  # Ensure the issue is on the board before setting its status.
  gh project item-add "$NUMBER" --owner "$OWNER" \
    --url "$(gh issue view <this-issue-number> --json url -q .url)"
  OWNER="$OWNER" NUMBER="$NUMBER" \
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
  ISSUE="<this-issue-number>" STATUS="Ready" \
    bash .github/scripts/project-status-set.sh
fi
```

`project-status.yml` only mirrors `In Review` and `Done` — it runs on PR
events, which don't exist yet at `analyze` time. (Where the server-side
`project-status-labeled.yml` is installed, applying `status: ready` also
moves the board; the sidecar call above stays as the desktop primary and
the two are idempotent.)

## Effort classification

| Level | Trigger                                                                            | Plan shape                                                                                          |
| ----- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| E0    | Typo, single-line fix, doc tweak, label rename, copy change.                       | No plan. One-paragraph guidance.                                                                    |
| E1    | Single file or two tightly coupled files. Clear, isolated.                         | ≤5 bullets: what, where, test.                                                                      |
| E2    | Multi-file within one domain. New endpoint, new component, refactor of one module. | Standard plan: goal, files, approach, test plan, rollback.                                          |
| E3    | Touches a domain in ``. Or: cross-cutting, public-API, data shape.   | Full plan + **Business impact** section + explicit risks + verification steps + rollback procedure. |

When unsure between two levels, pick the higher one.

### Keyword booster (soft signal)

When the issue title or body contains any of the following, lean toward
the higher level when in doubt:

- `breaking`, `breaking change`
- `security`, `vulnerability`, `CVE`
- `migration`, `migrate`
- `production data`, `prod data`
- `auth`, `authentication`, `authorization`
- `rollback`, `revert`

This is a **booster**, not a hard trigger — it pairs with the existing
"when unsure between two levels, pick the higher one" rule. It catches
issues where the diff is small but the context is risky.

## How to read the issue

- Title and body first.
- Linked issues / referenced PRs.
- Files mentioned by path or symbol — open and skim.
- Existing tests near those files — they tell you the shape of the seam.
- Comments thread — past decisions live there.

## Plan templates

### E1

```
**Plan**
- Change: <one sentence>
- File(s): <paths>
- Test: <how this gets verified>
```

### E2

```
**Plan**
- Goal: <outcome>
- Files: <paths>
- Approach: <2–4 bullets on the strategy>
- Test plan: <unit + any integration>
- Rollback: <how to undo if it goes wrong>
```

### E3

```
**Plan**
- Goal: <outcome>
- Business impact: <who/what is affected, severity, blast radius>
- Files: <paths>
- Approach: <ordered bullets>
- Risks: <bullets>
- Test plan: <unit, integration, manual checks>
- Rollback: <step-by-step>
- Verification post-deploy: <metrics, dashboards, log queries>
```

## Re-run policy

Before doing any work, **check whether this issue already has an
analyze artifact**:

- A previous comment authored by the bot/agent that looks like an
  analyze post (starts with `**Restatement**:` or contains the
  `**Effort**:` line as a top-level marker).
- An `effort/E0`–`effort/E3` label.
- A `status: ready` label.

If **any** of those exists, refuse loud — do **not** re-run silently
just because the user asked again in the same session. Silent re-run
diverges the in-session work from the canonical issue surface, which
is exactly the kind of fail-silent the workflow is designed to avoid.

Stop and reply:

> Issue #N already has an `/analyze` artifact (comment + effort
> label). Silently re-running would diverge what I produce in this
> session from what the issue records.
>
> If you want to redo the analysis, clean the canonical state first:
>
>   1. Delete the previous analyze comment on the issue.
>   2. Remove the `effort/*` and `status: ready` labels, and **re-apply
>      `status: backlog`** — the repo's contract (AGENTS.md → Required
>      labels) is that every open issue carries a status label, so
>      dropping `status: ready` without restoring `status: backlog`
>      leaves the issue without a state:
>      ```bash
>      gh issue edit <issue-number> \
>        --remove-label "status: ready" \
>        --add-label "status: backlog"
>      # Plus any effort/* label the previous analyze applied:
>      gh issue edit <issue-number> --remove-label "effort/E2"  # adjust to actual effort
>      ```
>   3. **If a Project v2 board is configured**, also move the issue back
>      to the `Backlog` column — labels alone won't update the board:
>      ```bash
>      OWNER=$(gh repo view --json owner -q .owner.login)
>      NUMBER=$(grep -E '^PROJECT_NUMBER=' .github/project.env 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]')
>      NUMBER=${NUMBER:-$(gh variable get PROJECT_NUMBER 2>/dev/null || echo "")}
>      if [ -n "$NUMBER" ]; then
>        OWNER="$OWNER" NUMBER="$NUMBER" \
>          REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
>          ISSUE="<this-issue-number>" STATUS="Backlog" \
>          bash .github/scripts/project-status-set.sh
>      fi
>      ```
>   4. Re-run `/analyze #N`.
>
> If you only want to edit details (e.g. the body of the existing
> plan), edit the comment directly rather than re-running.

The engineer or tech-lead owns the cleanup decision; the skill never
auto-overwrites the previous artifact.

## Hard rules

- No branches. No code edits. No PRs. Only an issue comment + label.
- If the issue is unclear, ask in **Open questions** — do not invent the spec.
- If the change touches anything in ``, the level is E3 — even
  if the diff would be small.
- Never re-run silently when an analyze artifact already exists on
  the issue. See "Re-run policy" above.

## MCP / web-session overrides

Apply this section **instead of** the `gh`/sidecar mechanics in the body
when you are in a web/mobile session without an authenticated `gh`. The
*what* of every step is unchanged — only the *how* differs. (Keep this
appendix in sync with the body whenever either changes — see
[#84](https://github.com/dsanchezvalle/workflow-template/issues/84).)

### Tooling contract

- **Resolve tools by capability, not prefix.** The canonical GitHub MCP
  names used here (`get_issue`, `get_issue_comments`, `add_issue_comment`,
  `update_issue`) may be exposed under a server-specific prefix — match by
  name suffix.
- **No GitHub MCP server connected → fail loud.** Stop and tell the human:
  connect the GitHub MCP integration, or run this issue in a desktop
  session where `gh` is available. Never fall back to unauthenticated REST
  calls or to guessing repo state.
- **Field discipline (token efficiency).** Pick the narrowest tool that
  answers the question; cap page sizes on list calls; after each call keep
  only the fields the step needs and drop the rest. Never re-fetch an
  object already read this session. Never quote a full MCP payload into the
  conversation, an issue comment, or any artifact.

### Step overrides

- **Read the issue** with one `get_issue` call (title, body, labels — keep
  those fields only); read the thread with `get_issue_comments` (capped
  page size, author + body only).
- **Post the plan comment** with `add_issue_comment`.
- **Apply labels** with read-modify-write: most servers' `update_issue`
  replaces the full label set, so take the current `labels[].name` you
  already read, compute new set = current − {`status: backlog`} +
  {`status: ready`, `effort/E<n>`}, and write it back with `update_issue`
  (prefer dedicated add/remove-label tools if the server exposes them).
- **Board sync is server-side — never from the session.** Do not invoke
  the sidecar and do not call `gh project`. Applying `status: ready` is the
  whole job: `project-status-labeled.yml` moves the card to Ready, reading
  the number from `.github/project.env`. If the board doesn't move, check
  that workflow's run log — it fails loud there.
- **Re-run cleanup** (when an analyze artifact already exists): delete the
  previous comment via the MCP delete-comment tool (or the GitHub UI); swap
  labels back to `status: backlog` with the same read-modify-write. The
  board move-back is automatic — re-applying `status: backlog` triggers the
  labeled workflow. No manual board step, no sidecar.
