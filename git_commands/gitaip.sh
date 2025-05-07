#!/bin/bash

set -e

# Ensure API key is present
if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "Error: OPENAI_API_KEY is not set"
  exit 1
fi

# Exit if in the middle of a merge conflict
if git ls-files -u | grep -q .; then
  echo "❌ Merge conflict detected. Please resolve it before using this command."
  exit 1
fi

# Add all modified (but unstaged) files
MODIFIED=$(git ls-files -m)
if [[ -n "$MODIFIED" ]]; then
  echo "🔄 Staging modified files..."
  git add -u
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

DIFF_LIMIT=8000
GIT_DIFF=$(git diff --cached)
DIFF_SIZE=$(echo "$GIT_DIFF" | wc -c)
if [ "$DIFF_SIZE" -lt "$DIFF_LIMIT" ]; then
  PROMPT="You are an expert software engineer writing for a git tool.

Your job is to:
1. Suggest a short and descriptive **branch name**, lowercase with dashes (e.g., feat/add-minting-check).
2. Suggest a semantic **commit message** starting with a prefix like \`feat:\`, \`fix:\`, \`refactor:\`, etc.
3. Provide a concise **PR body** explaining what changed and why.

❗Important formatting rules:
- Use **plain text only**. Do not wrap any output in backticks, quotes, or markdown headers.
- Separate output sections clearly using labels exactly as shown below.

Format:
Branch name:
<plain-text-branch-name>

Commit message:
<semantic commit message>

PR Body:
<1–3 short paragraphs explaining the change>

Context:
$GIT_DIFF"
else
  FILES=$(git diff --cached --name-only)
  METHODS=$(git diff --cached | grep -E '^[+][[:space:]]*(pub|fn|def|function)' | sed -E 's/^[+][[:space:]]*//')
  PROMPT="You are an expert software engineer writing for a git tool.

Your job is to:
1. Suggest a short and descriptive **branch name**, lowercase with dashes (e.g., feat/add-minting-check).
2. Suggest a semantic **commit message** starting with a prefix like \`feat:\`, \`fix:\`, \`refactor:\`, etc.
3. Provide a concise **PR body** explaining what changed and why.

❗Important formatting rules:
- Use **plain text only**. Do not wrap any output in backticks, quotes, or markdown headers.
- Separate output sections clearly using labels exactly as shown below.

Format:
Branch name:
<plain-text-branch-name>

Commit message:
<semantic commit message>

PR Body:
<1–3 short paragraphs explaining the change>

Context:
Changed files:
$FILES

Method definitions:
$METHODS"
fi

TMP_PROMPT=$(mktemp)
echo "$PROMPT" > "$TMP_PROMPT"

feedback=""
while true; do
  FINAL_PROMPT="$PROMPT"
  if [[ -n "$feedback" ]]; then
    FINAL_PROMPT+="\n\nUser feedback: $feedback"
  fi

  RESPONSE=$(curl -sS -w "\n%{http_code}" https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": $(jq -Rs '.' <<< "$FINAL_PROMPT")}],
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
    exit 1
  fi

  OUTPUT=$(echo "$HTTP_BODY" | jq -r '.choices[0].message.content // empty')

  # Extract sections from AI response
  BRANCH=$(echo "$OUTPUT" | awk '/^[Bb]ranch name:/ { getline; print; exit }' | xargs)
  MESSAGE=$(echo "$OUTPUT" | awk '/^[Cc]ommit message:/ { getline; print; exit }' | xargs)
  BODY=$(echo "$OUTPUT" | awk '/^[Pp][Rr] [Bb]ody:/ {flag=1; next} flag' | sed '/^\s*$/d')
  
  if [[ -z "$BRANCH" || -z "$MESSAGE" ]]; then
    echo "❌ Could not parse AI response. Raw content:"
    echo "$OUTPUT"
    exit 1
  fi

  echo "📝 Proposed Branch: $BRANCH"
  echo "📝 Commit Message: $MESSAGE"
  echo -e "📝 PR Body:\n$BODY"

  read -p "❓ Is this okay? (y/n/feedback): " confirm
  case "$confirm" in
    y|Y|yes|YES)
      read -p "❗ Is this a breaking change? (y/N): " breaking
      [[ "$breaking" =~ ^[yY]$ ]] && MESSAGE="${MESSAGE/://!:}"
      break
      ;;
    n|N|no|NO)
      echo "Aborted by user."
      exit 1
      ;;
    *)
      feedback="$confirm"
      ;;
  esac
done

BRANCH_SANITIZED=$(echo "$BRANCH" | tr ' ' '-' | tr -cd '[:alnum:]-')
git checkout -b "$BRANCH_SANITIZED"
echo "✅ Using commit message: $MESSAGE"
git commit -m "$MESSAGE"
git push origin "$BRANCH_SANITIZED"

# Create PR
gh pr create --base "$CURRENT_BRANCH" --head "$BRANCH_SANITIZED" --title "$MESSAGE" --body "$BODY"
echo "✅ PR created targeting $CURRENT_BRANCH from $BRANCH_SANITIZED"
