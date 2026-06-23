---
name: changelog-reporter
description: Append a date-grouped entry to CHANGELOG.md when commits land on develop. Use when the user says "update the changelog" or as part of the generate-changelog workflow.
---

# changelog-reporter

Date-based, no version numbers. The changelog is a human-readable log of what
changed and when, not a release artifact.

## Trigger

Push to `develop`. The `generate-changelog.yml` workflow invokes this skill
in CI — it skips its own `chore(changelog): update` commits via a job-level
`if:` subject guard (not `[skip ci]`, which would poison the develop→main
release boundary). Locally, the user can invoke it manually.

## Behavior

1. Determine the cut: read the most recent date heading in `CHANGELOG.md`
   (format `## YYYY-MM-DD`). Collect all merge-commit subjects on `develop`
   since that date.
   - If `CHANGELOG.md` does not exist, create it.
   - If no heading exists, collect from the first commit.
2. Group commits by **today's date** (UTC):
   ```
   ## YYYY-MM-DD

   - <type>: <subject> (#<issue>)
   - ...
   ```
3. Order within a date: `feat` first, then `fix`, then everything else,
   alphabetical within each group.
4. Skip commits whose subject contains `[skip changelog]`.
5. Skip merge commits whose only purpose is back-merge (`back-merge: ...`).
6. Commit the change with subject `chore(changelog): update`. Do **not** add
   `[skip ci]`: the bot pushes with `GITHUB_TOKEN` (which never re-triggers
   workflows), and a `[skip ci]` marker would later block the develop→main
   release PR and silence back-merge on the squash to main. The
   workflow excludes this commit from future runs by matching its subject.

## Format invariants

- No version numbers. No `vX.Y.Z` headings.
- Date format strictly `YYYY-MM-DD` in UTC.
- Issue references as GitHub auto-links: `(#123)` not full URLs.
- One blank line between sections.

## Hard rules

- Never rewrite history. Only append above the most recent date heading or
  add a new heading.
- Never include the closing-keyword form (`fixes #123`); use the bare
  reference `(#123)`. Closing keywords on `develop` would close the issue
  prematurely.
- If the workflow runs with no new commits to report, exit 0 and write
  nothing.
