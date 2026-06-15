#!/usr/bin/env bash
# CORE: agnostic
# Sets the Status field of a Project v2 item that links to the given issue.
#
# Required env vars:
#   OWNER     — project owner (user or org login)
#   NUMBER    — project number (integer)
#   REPO      — "owner/name" of the repo containing the issue
#   ISSUE     — issue number
#   STATUS    — option name (must match a Status field option in the project)
#
# Optional env vars:
#   GH_TOKEN  — token with project + repo scopes. If unset, falls back to
#               `gh auth token` so session-side callers (skills) don't have
#               to export anything; CI runs always pass it explicitly.
#
# Fails loudly if the project, field, option, or item cannot be resolved.
set -euo pipefail

: "${OWNER:?missing}"
: "${NUMBER:?missing}"
: "${REPO:?missing}"
: "${ISSUE:?missing}"
: "${STATUS:?missing}"

# D1: skills invoke this sidecar without exporting GH_TOKEN. Fall back to
# the user's gh auth token so the session path works; keep the loud
# failure if neither is available.
if [ -z "${GH_TOKEN:-}" ]; then
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  if [ -z "$GH_TOKEN" ]; then
    echo "::error::GH_TOKEN unset and 'gh auth token' returned nothing" >&2
    exit 1
  fi
  export GH_TOKEN
fi

# 1. Resolve the project's node id, the Status field id, and the matching
# option id via the polymorphic repositoryOwner(login:) root, which works
# on both User and Organization owners. The previous combined
# user{} + organization{} query made `gh api graphql` exit non-zero on
# the wrong resolver (NOT_FOUND), aborting the script before any fallback.
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
  '(.data.repositoryOwner.projectV2.field.options // [])[]
    | select(.name == $s) | .id' <<<"$PROJECT_JSON")

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
# D4: GraphQL's `after` argument is a nullable String. Passing the literal
# string "null" with `-f` typed the cursor as the string "null" and the
# API rejected the first page with "after does not appear to be a valid
# cursor". Use a distinct query shape for the first page (no `after`) and
# pass real cursors with `-f` on subsequent pages.
ITEM_ID=""
CURSOR=""
while :; do
  if [ -z "$CURSOR" ]; then
    PAGE=$(gh api graphql -f query='
      query($pid:ID!){
        node(id:$pid){
          ... on ProjectV2{
            items(first:100){
              pageInfo{ endCursor hasNextPage }
              nodes{ id content{ ... on Issue{ id } } }
            }
          }
        }
      }' -f pid="$PROJECT_ID")
  else
    PAGE=$(gh api graphql -f query='
      query($pid:ID!,$cursor:String!){
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
