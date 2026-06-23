---
name: deploy-pipeline
description: Run the pre-deploy checklist for Node 20 + static site (HTML/CSS/JS). Use when the user says "ready to deploy", "deploy checklist", or before merging a release PR to main.
---

# deploy-pipeline

Stack-aware pre-deploy gate. **Filled at setup time** from `context.yml`.

## Default checklist (always)

- [ ] `develop` is green on CI.
- [ ] Release PR `develop → main` exists, is approved, and CI is green.
- [ ] No closing keywords (`closes/fixes/resolves #N`) in the PR title or
      body — `validate-release-pr.yml` will reject them.
- [ ] CHANGELOG entry covers everything in this release.
- [ ] No unmerged hotfixes pending on `main`.

## Build & verify

- [ ] `npm run lint` passes locally.
- [ ] `npm run typecheck` passes locally.
- [ ] `npm test` passes locally.
- [ ] `npm run build` succeeds locally.

## Environment & config

- [ ] All required env vars present in the target environment ().
- [ ] Secrets rotated if any leaked path was touched.
- [ ] Feature flags for this release are configured in the target env.

## Data layer

- [ ] Migrations are reversible and tested on a copy of prod data.
- [ ] Backfills (if any) are idempotent and chunked.
- [ ] Indexes added with the appropriate online/concurrent strategy for
      ``.

## Rollback

- [ ] Rollback procedure documented in the release PR body.
- [ ] Previous artifact / image / build is still available.
- [ ] Owner identified for the next 24h.

## Stack-specific notes (Node 20 + static site (HTML/CSS/JS))



## Hard rules

- If any unchecked item is unchecked at deploy time, stop and surface it.
- Never bypass the release PR. No direct push to `main`.
