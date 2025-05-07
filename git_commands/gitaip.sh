#!/bin/bash

set -e

# Ensure API key is present
if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "Error: OPENAI_API_KEY is not set"
  exit 1
fi

# Ensure staged changes exist
git diff --cached --quiet && {
  echo "No staged changes detected. Please stage your changes with 'git add' before running this command."
  exit 0
}

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ ! "$CURRENT_BRANCH" =~ ^(v[0-9]+-dev|master|develop)$ ]]; then
  echo "You are on branch '$CURRENT_BRANCH'. This command will create a PR targeting this branch."
  read -p "Are you sure you want to continue? (y/n): " confirm
  if [[ "$confirm" != "y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# Generate prompt
DIFF_LIMIT=8000
GIT_DIFF=$(git diff --cached)
DIFF_SIZE=$(echo "$GIT_DIFF" | wc -c)

if [ "$DIFF_SIZE" -lt "$DIFF_LIMIT" ]; then
  PROMPT=$(cat <<EOF
You are an expert software engineer. Analyze the following git diff and:
1. Propose a succinct git branch name (e.g., fix/validate-ids, feat/token-distribution).
2. Propose a clear commit message.

Diff:
$GIT_DIFF
EOF
)
else
  FILES=$(git diff --cached --name-only)
  METHODS=$(git diff --cached | grep -E '^[+][[:space:]]*(pub|fn|def|function)' | sed -E 's/^[+][[:space:]]*//')
  PROMPT=$(cat <<EOF
You are an expert software engineer. Analyze this set of changed files and methods to:
1. Suggest a descriptive git branch name.
2. Propose a clear commit message.

Changed files:
$FILES

Method definitions:
$METHODS
EOF
)
fi

# Save prompt to a temp file for debugging
TMP_PROMPT=$(mktemp)
echo "$PROMPT" > "$TMP_PROMPT"

# Call OpenAI
RESPONSE=$(curl -sS -w "\n%{http_code}" https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": $(jq -Rs '.' < "$TMP_PROMPT")}],
  "temperature": 0.4
}
EOF
)

HTTP_BODY=$(echo "$RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "❌ OpenAI API request failed with status $HTTP_CODE"
  echo "➡️ Response body:"
  echo "$HTTP_BODY"
  echo "➡️ Prompt used (saved to $TMP_PROMPT):"
  cat "$TMP_PROMPT"
  exit 1
fi

OUTPUT=$(echo "$HTTP_BODY" | jq -r '.choices[0].message.content // empty')

if [[ -z "$OUTPUT" ]]; then
  echo "❌ No content in AI response. Raw response:"
  echo "$HTTP_BODY"
  exit 1
fi

BRANCH=$(echo "$OUTPUT" | grep -E 'branch name:|Branch name:|^1[).] ' | head -n1 | sed -E 's/.*[Bb]ranch name[:\)]?[[:space:]]*//; s/^1[).] //')
MESSAGE=$(echo "$OUTPUT" | grep -A1 -i 'commit message' | tail -n1)

if [[ -z "$BRANCH" || -z "$MESSAGE" ]]; then
  echo "❌ Could not parse AI response. Raw content:"
  echo "$OUTPUT"
  exit 1
fi

BRANCH_SANITIZED=$(echo "$BRANCH" | tr ' ' '-' | tr -cd '[:alnum:]-')
git checkout -b "$BRANCH_SANITIZED"
echo "✅ Using commit message: $MESSAGE"
git commit -m "$MESSAGE"
git push origin "$BRANCH_SANITIZED"

# Create PR
gh pr create --base "$CURRENT_BRANCH" --head "$BRANCH_SANITIZED" --title "$MESSAGE" --body "$MESSAGE"
echo "✅ PR created targeting $CURRENT_BRANCH from $BRANCH_SANITIZED"