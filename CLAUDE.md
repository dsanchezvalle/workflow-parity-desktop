<!-- ADAPTER: claude -->
# workflow-parity-desktop — Operating Guide

This file is the entry point for Claude Code in this repository. Keep it short
and current; deep detail belongs in the linked skills and in
[AGENTS.md](AGENTS.md).

## What this project is

- **Domain:** A minimal static marketing site (a homepage plus an about page) used as
a throwaway fixture for the workflow-template twin-repo parity test
(issue dsanchezvalle/workflow-template#67). The site is intentionally
tiny so issues exercise the workflow, not the implementation.
- **Stack:** Node 20 + static site (HTML/CSS/JS)
- **Code language:** en
- **UI / user-facing language:** en
- **Hosting / runtime:** 
- **Data layer:** 

## Workflow at a glance

Issue → `analyze` → human-approved plan → `start` → `code-review (plan)` →
implement → `code-review (code)` → `verify-sync` → push → PR → merge to
`develop` → release PR to `main`.

Branching:

- `main` — production. Protected. Only release PRs from `develop` land here.
- `develop` — integration. Default branch. PRs from feature branches land here.
- Feature branches: `feat/<issue>-slug`, `fix/<issue>-slug`, `docs/<issue>-slug`,
  `refactor/<issue>-slug`, `chore/<issue>-slug`, `test/<issue>-slug`.

Commits: [Conventional Commits](https://www.conventionalcommits.org/).

> **Enforcement gap**: this template does not run commitlint or any
> hard pre-commit check. Conventional Commits is honored by author
> discipline plus human PR review. The only automated enforcement is
> `validate-release-pr.yml` (rejects closing keywords on develop → main
> PRs) and the regex-based filter in `generate-changelog.yml` (commits
> not matching `^(feat|fix|...): ` are silently dropped from the
> changelog). Authors writing `wip` or `update` commits will produce
> empty changelog entries.

## Skill index

Invoke these via natural language; the harness routes by description.

| Skill                                          | When to use                                              |
| ---------------------------------------------- | -------------------------------------------------------- |
| [analyze](.claude/skills/analyze.md)           | Triage an issue, classify E0–E3, post a plan.            |
| [start](.claude/skills/start.md)               | Begin implementation after plan approval.                |
| [code-review](.claude/skills/code-review.md)   | Review plan (pre-impl) or code (pre-merge).              |
| [deploy-pipeline](.claude/skills/deploy-pipeline.md) | Pre-deploy checklist for this stack.                     |
| [changelog-reporter](.claude/skills/changelog-reporter.md) | Append a date-based changelog entry on merge to develop. |
| [verify-sync](.claude/skills/verify-sync.md)   | Verify CLAUDE.md / AGENTS.md ↔ workflows are in sync.    |

## Project conventions

- **Lint:** `npm run lint`
- **Typecheck:** `npm run typecheck`
- **Test:** `npm test`
- **Build:** `npm run build`
- **Run dev:** `npm run dev`

Hot paths (read these before changing them): src

## Effort classification (E0–E3)

`analyze` classifies every issue:

- **E0** — direct guidance, no plan needed (typos, single-line fixes, doc tweaks).
- **E1** — short plan (≤5 bullets). Single file or small isolated change.
- **E2** — standard plan. Multi-file change within one domain.
- **E3** — full plan + business-impact section. Triggered for any issue
  touching: .

> The list above is editable. `analyze` reads it from this file on every
> invocation — no re-setup needed. Add new high-blast-radius areas as
> they emerge, remove ones that no longer apply.

## What to NOT do here

- Do not bypass `start` to commit directly. The orchestration enforces review.
- Do not change branch protections or CI workflows without an issue.
- Do not introduce dependencies without justifying them in the plan.

## Pointers

- [AGENTS.md](AGENTS.md) — flow definitions, skill specs, escalation rules.
- `.github/workflows/` — CI, auto-PR, project lifecycle, changelog, doc sync.
