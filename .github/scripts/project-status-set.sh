#!/usr/bin/env bash
# CORE: agnostic
# Sets the Status field of a Project v2 item that links to the given issue.
#
# TEST-ONLY PATCH (twin-repo parity test — workflow-template#67 / #78).
# This file diverges from the canonical pack in three ways so the desktop
# board can sync on a user-owned account:
#   1. GH_TOKEN falls back to `gh auth token` when not exported
#      (canonical: hard-required env var, so session-side skill calls fail).
#   2. Project meta resolves via the polymorphic repositoryOwner(login:)
#      root (canonical: combined top-level user(...) + organization(...)
#      query, which errors with NOT_FOUND on user accounts and aborts).
#   3. Item pagination omits `after` on the first page (canonical seeds the
#      literal string "null" as the cursor, which GraphQL rejects).
# The canonical pack stays unpatched on purpose; audit verdicts for this
# repo record the as-shipped behavior as FAIL. See workflow-template#78.
#
# Required env vars:
#   GH_TOKEN  — token with project + repo scopes (falls back to gh keyring)
#   OWNER     — project owner (org or user login)
#   NUMBER    — project number (integer)
#   REPO      — "owner/name" of the repo containing the issue
#   ISSUE     — issue number
#   STATUS    — option name (must match a Status field option in the project)
#
# Fails loudly if the project, field, option, or item cannot be resolved.
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ]; then
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  export GH_TOKEN
fi
: "${GH_TOKEN:?missing — export GH_TOKEN or authenticate gh first}"
: "${OWNER:?missing}"
: "${NUMBER:?missing}"
: "${REPO:?missing}"
: "${ISSUE:?missing}"
: "${STATUS:?missing}"

# 1. Resolve the project's node id, the Status field id, and the matching
# option id. repositoryOwner is the polymorphic root: it resolves whether
# $OWNER is a User or an Organization, and both fragments collapse to the
# same .data.repositoryOwner.projectV2 shape.
PROJECT_JSON=$(gh api graphql -f query='
  query($owner:String!,$number:Int!){
    repositoryOwner(login:$owner){
      ... on User{
        projectV2(number:$number){
          id
          field(name:"Status"){
            ... on ProjectV2SingleSelectField{
              id
              options{ id name }
            }
          }
        }
      }
      ... on Organization{
        projectV2(number:$number){
          id
          field(name:"Status"){
            ... on ProjectV2SingleSelectField{
              id
              options{ id name }
            }
          }
        }
      }
    }
  }' -f owner="$OWNER" -F number="$NUMBER")

PROJECT_ID=$(jq -r '.data.repositoryOwner.projectV2.id // empty' <<<"$PROJECT_JSON")
FIELD_ID=$(jq -r '.data.repositoryOwner.projectV2.field.id // empty' <<<"$PROJECT_JSON")
OPTION_ID=$(jq -r --arg s "$STATUS" \
  '((.data.repositoryOwner.projectV2.field.options // [])[]
    | select(.name == $s) | .id)' <<<"$PROJECT_JSON")

if [ -z "$PROJECT_ID" ]; then
  echo "::error::Project v2 #$NUMBER not found under $OWNER" >&2
  exit 1
fi
if [ -z "$FIELD_ID" ]; then
  echo "::error::Project $OWNER/#$NUMBER has no 'Status' single-select field" >&2
  exit 1
fi
if [ -z "$OPTION_ID" ]; then
  echo "::error::Status field has no option named '$STATUS'" >&2
  exit 1
fi

# 2. Find the project item id for this issue.
ISSUE_NODE_ID=$(gh api graphql -f query='
  query($repo:String!,$owner:String!,$num:Int!){
    repository(owner:$owner,name:$repo){
      issue(number:$num){ id }
    }
  }' -f repo="${REPO#*/}" -f owner="${REPO%%/*}" -F num="$ISSUE" \
  | jq -r '.data.repository.issue.id // empty')

if [ -z "$ISSUE_NODE_ID" ]; then
  echo "::error::Issue $REPO#$ISSUE not found" >&2
  exit 1
fi

# Page through project items until we find one whose content node id matches.
# TEST-ONLY PATCH (workflow-template#67/#78), defect 4: the canonical loop
# seeds CURSOR="null" and passes it with -f (raw string), so GraphQL gets
# the literal string "null" as the cursor and rejects the very first page
# ("after does not appear to be a valid cursor"). First page must omit the
# cursor; later pages pass the real endCursor.
ITEM_ID=""
CURSOR=""
while :; do
  if [ -z "$CURSOR" ]; then
    PAGE=$(gh api graphql -f query='
      query($pid:ID!,$cursor:String){
        node(id:$pid){
          ... on ProjectV2{
            items(first:100, after:$cursor){
              pageInfo{ endCursor hasNextPage }
              nodes{ id content{ ... on Issue{ id } } }
            }
          }
        }
      }' -f pid="$PROJECT_ID")
  else
    PAGE=$(gh api graphql -f query='
      query($pid:ID!,$cursor:String){
        node(id:$pid){
          ... on ProjectV2{
            items(first:100, after:$cursor){
              pageInfo{ endCursor hasNextPage }
              nodes{ id content{ ... on Issue{ id } } }
            }
          }
        }
      }' -f pid="$PROJECT_ID" -f cursor="$CURSOR")
  fi
  ITEM_ID=$(jq -r --arg iid "$ISSUE_NODE_ID" \
    '.data.node.items.nodes[] | select(.content.id == $iid) | .id' <<<"$PAGE" | head -n1)
  if [ -n "$ITEM_ID" ]; then break; fi
  HAS_NEXT=$(jq -r '.data.node.items.pageInfo.hasNextPage' <<<"$PAGE")
  if [ "$HAS_NEXT" != "true" ]; then break; fi
  CURSOR=$(jq -r '.data.node.items.pageInfo.endCursor' <<<"$PAGE")
done

if [ -z "$ITEM_ID" ]; then
  echo "::error::Issue $REPO#$ISSUE is not a draft/issue item on project $OWNER/#$NUMBER" >&2
  exit 1
fi

# 3. Mutate.
gh api graphql -f query='
  mutation($pid:ID!,$item:ID!,$field:ID!,$opt:String!){
    updateProjectV2ItemFieldValue(
      input:{ projectId:$pid, itemId:$item, fieldId:$field,
              value:{ singleSelectOptionId:$opt } }
    ){ projectV2Item{ id } }
  }' -f pid="$PROJECT_ID" -f item="$ITEM_ID" -f field="$FIELD_ID" -f opt="$OPTION_ID" >/dev/null

echo "Project $OWNER/#$NUMBER: issue #$ISSUE -> Status='$STATUS'"
