<!-- CORE: agnostic -->
---
name: verify-sync
description: Verify that CLAUDE.md, AGENTS.md, and .github/workflows/ describe the same reality — bidirectionally. Use when docs or workflows changed, before pushing, and inside the start orchestration.
---

# verify-sync

Catches the failure mode where CLAUDE.md says one thing and the workflows do
another, or vice versa. Bidirectional — both directions are checked.

## What it checks

### Docs → reality

- Every skill listed in `CLAUDE.md` resolves to an existing file at the
  given path under `.claude/skills/`.
- Every workflow filename mentioned in `CLAUDE.md` or `AGENTS.md` exists at
  `.github/workflows/<name>.yml`.
- The branch model described in `CLAUDE.md` (default branch, feature
  prefixes) matches the triggers in `ci.yml` and `auto-pr.yml`.
- The Conventional Commit prefix list in `CLAUDE.md` matches what
  `validate-release-pr.yml` and any commit linters accept.

### Reality → docs

- Every file under `.claude/skills/*.md` is referenced in the `CLAUDE.md`
  skill index. (No orphaned skills.)
- Every file under `.github/workflows/*.yml` is described in `AGENTS.md` (in
  the flow diagram or the skill specs section). (No orphaned workflows.)
- Every script under `scripts/` referenced by a workflow exists.

## Semantic checks (beyond what `check-docs-sync.yml` catches)

The structural CI workflow catches missing files and missing references.
The semantic pass catches drift in **behavior described**:

1. **Branch model coherence** — if `CLAUDE.md` says the default branch
   is `develop`, every relevant workflow trigger must include
   `develop` (and `main` where appropriate). Missing trigger = silent
   drift.
2. **Conventional Commit prefix list** — the prefixes named in
   `CLAUDE.md` (`feat`, `fix`, etc.) must match what
   `validate-release-pr.yml` accepts and what `generate-changelog.yml`
   regex-matches. Adding a prefix to docs without updating both
   workflows = changelog gaps.
3. **Skill behavior contract** — if `AGENTS.md` describes a skill's
   preconditions or hard rules, the skill's own `.md` must enforce
   them. Drift between `AGENTS.md` and the skill file = the contract
   is wrong somewhere.
4. **Label set consistency** — the canonical labels in
   `AGENTS.md → Required labels` (this destination repo) must equal:
     - the `gh label create` list in `github-driven/setup/github-checklist.md`
       **in the workflow-template clone** (not in this destination repo), and
     - the `canonical` array in `github-driven/scripts/verify.sh`
       **in the workflow-template clone** (same).
   Three sources of truth must agree. When this skill runs in the
   destination repo, only `AGENTS.md` is inspectable here; the two
   template-side paths are pointers for the human/agent to cross-check
   when drift is suspected.

The skill reports drift; the human or `start` orchestrator decides.
This skill **never auto-fixes**.

## Output

```
verify-sync: PASS
```
or
```
verify-sync: FAIL

Docs → reality:
  - <issue>
  - <issue>

Reality → docs:
  - <issue>
```

Each issue is one line, file path included.

## Exit code

- `0` on PASS.
- `1` on FAIL.

## Hard rules

- Never auto-fix. Report; the human or the orchestrator decides.
- Never weaken a check by ignoring it — if a check is wrong, change it
  in this file with a real reason.
- Run before every push that touches docs or workflows. `start` invokes
  this automatically.
