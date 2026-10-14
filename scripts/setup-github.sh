#!/usr/bin/env bash
# setup-github.sh — create the private GitHub repo, push the skeleton, create teams and protect main.
#
# Usage (from the repo root, with the GitHub CLI logged in as an org admin):
#   ./scripts/setup-github.sh <github-org-or-user> [repo-name]
#
# Example:
#   ./scripts/setup-github.sh amzur-tech pixorex
#
# Safe to re-run: existing repo/teams are reused, protection is re-applied.

set -euo pipefail

OWNER="${1:?usage: setup-github.sh <org-or-user> [repo-name]}"
REPO="${2:-pixorex}"
FULL="${OWNER}/${REPO}"

command -v gh >/dev/null || { echo "Install the GitHub CLI: https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null || { echo "Run: gh auth login" >&2; exit 1; }
[[ -f CONSTITUTION.md ]] || { echo "Run this from the repo root." >&2; exit 1; }

IS_ORG=false
if gh api "orgs/${OWNER}" >/dev/null 2>&1; then IS_ORG=true; fi

# --- 1. CODEOWNERS: point the placeholders at this owner ------------------------------
sed -i.bak "s#@OWNER/#@${OWNER}/#g" .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
if [[ "$IS_ORG" != true ]]; then
  echo "Note: ${OWNER} is a user account, so team handles in CODEOWNERS will not resolve."
  echo "      Edit .github/CODEOWNERS to list individual @usernames instead."
fi

# --- 2. First commit and push ---------------------------------------------------------
if [[ ! -d .git ]]; then
  git init -b main
fi
git add -A
if ! git diff --cached --quiet; then
  git commit -m "PX-00-T00: repository skeleton, governance files and CI gates"
fi

if gh repo view "$FULL" >/dev/null 2>&1; then
  echo "Repo ${FULL} exists; pushing."
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/${FULL}.git"
  git push -u origin main
else
  gh repo create "$FULL" --private --source . --remote origin --push \
    --description "Pixorex V1 — AI-powered industrial asset digitization"
fi

# --- 3. Repo settings: squash only, auto-delete branches -------------------------------
gh api -X PATCH "repos/${FULL}" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true >/dev/null

# --- 4. Teams (org only) ---------------------------------------------------------------
if [[ "$IS_ORG" == true ]]; then
  for team in pixorex-architects pixorex-devs pixorex-devops; do
    if ! gh api "orgs/${OWNER}/teams/${team}" >/dev/null 2>&1; then
      gh api -X POST "orgs/${OWNER}/teams" -f name="$team" -f privacy=closed >/dev/null \
        && echo "Created team ${team}" || echo "Could not create team ${team} (need org admin?)"
    fi
    perm=push; [[ "$team" == pixorex-architects ]] && perm=maintain
    gh api -X PUT "orgs/${OWNER}/teams/${team}/repos/${FULL}" -f permission="$perm" >/dev/null \
      || echo "Could not grant ${team} access to ${FULL}"
  done
fi

# --- 5. Protect main --------------------------------------------------------------------
# Required checks are the ones that run on every PR. Add api/web/mobile jobs here once
# PX-10-T04 makes them run on every PR (path-filtered jobs would block unrelated PRs).
gh api -X PUT "repos/${FULL}/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["pr-rules", "secret-scan", "sast", "dependency-scan"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

echo
echo "Done: https://github.com/${FULL}"
echo "Next:"
echo "  1. Add people to the teams: architects (Geetashish, Suchith), devs, devops."
echo "  2. Drop the OpenAPI files into contracts/ in the first PR."
echo "  3. Each engineer: git clone, make up, read README.md."
