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

# Add all modified or added files
MODIFIED_OR_ADDED=$(git status --porcelain | grep -E '^( M|A |\?\?)' || true)
if [[ -n "$MODIFIED_OR_ADDED" ]]; then
  echo "🔄 Staging modified and added files..."
  git add -A
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

read -p "📋 Would you like to use the advanced pull request template? (y/N/A for always): " use_template

ADVANCED_TEMPLATE=false
if [[ "$use_template" =~ ^[yY](es)?$ ]]; then
  ADVANCED_TEMPLATE=true
elif [[ "$use_template" =~ ^[aA]$ ]]; then
  ADVANCED_TEMPLATE=true
  echo "ADVANCED_TEMPLATE=true" > .gitaipconfig
  # Ensure .gitaipconfig is ignored by Git
  if [[ -f .gitignore && -w .gitignore ]]; then
    if ! grep -q "^.gitaipconfig$" .gitignore; then
      echo ".gitaipconfig" >> .gitignore
      echo "📄 Added .gitaipconfig to .gitignore"
    fi
  fi
elif [[ -f .gitaipconfig && $(grep ADVANCED_TEMPLATE .gitaipconfig) == "ADVANCED_TEMPLATE=true" ]]; then
  ADVANCED_TEMPLATE=true
fi

DIFF_LIMIT=8000
GIT_DIFF=$(git diff --cached)
DIFF_SIZE=$(echo "$GIT_DIFF" | wc -c)

if [ "$DIFF_SIZE" -lt "$DIFF_LIMIT" ]; then
  CONTEXT="Diff:
$GIT_DIFF"
else
  FILES=$(git diff --cached --name-only)
  METHODS=$(git diff --cached | grep -E '^[+][[:space:]]*(pub|fn|def|function)' | sed -E 's/^[+][[:space:]]*//')
  CONTEXT="Changed files:
$FILES

Method definitions:
$METHODS"
fi

if $ADVANCED_TEMPLATE; then
PROMPT="You are an expert software engineer writing for a git tool.

Your job is to:
1. Suggest a short and descriptive **branch name**, lowercase with dashes (e.g., feat/add-minting-check).
2. Suggest a semantic **commit message** starting with a prefix like feat:, fix:, refactor:, etc.
3. Provide a concise **PR body** explaining what changed and why.

Format your PR body with the following (but don't include what's in parenthesis):
- ## Issue being fixed or feature implemented
- ## What was done?
- ## How Has This Been Tested?
- ## Breaking Changes (write 'None' if none)
- ## Checklist
  - [ ] I have performed a self-review of my own code
  - [ ] I have commented my code, particularly in hard-to-understand areas (try to figure out if this should be checked, if you see enough comments automatically check this)
  - [ ] I have added or updated relevant unit/integration/functional/e2e tests (try to figure out if things were tested, if they were, automatically check this)
  - [x] I have added "!" to the title and described breaking changes in the corresponding section if my code contains any.

  **For repository code-owners and collaborators only**
  - [ ] I have assigned this pull request to a milestone

Format:
Branch name:
<branch>

Commit message:
<semantic commit message>

PR Body:
<PR content in appropriate format>

$CONTEXT"
else
  PROMPT="You are an expert software engineer writing for a git tool.

  Your job is to:
  1. Suggest a short and descriptive **branch name**, lowercase with dashes (e.g., feat/add-minting-check).
  2. Suggest a semantic **commit message** starting with a prefix like feat:, fix:, refactor:, etc.
  3. Provide a concise **PR body** explaining what changed and why.

  Format:
  Branch name:
  <branch>

  Commit message:
  <semantic commit message>

  PR Body:
  <PR content in appropriate format>

  $CONTEXT"
fi

TMP_PROMPT=$(mktemp)
echo "$PROMPT" > "$TMP_PROMPT"

feedback=""
while true; do
  FINAL_PROMPT="$PROMPT"
  [[ -n "$feedback" ]] && FINAL_PROMPT+="\n\nUser feedback: $feedback"

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

  # Extract branch name
  BRANCH=$(echo "$OUTPUT" | awk '
    tolower($0) ~ /^branch name:/ {
      val = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+/, "", val)
      if (length(val) > 0) {
        print val
        exit
      }
      else {
        getline
        print
        exit
      }
    }' | xargs)

  # Extract commit message
  MESSAGE=$(echo "$OUTPUT" | awk '
    tolower($0) ~ /^commit message:/ {
      val = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+/, "", val)
      if (length(val) > 0) {
        print val
        exit
      }
      else {
        getline
        print
        exit
      }
    }' | xargs)
  BODY=$(echo "$OUTPUT" | awk '/^[Pp][Rr] [Bb]ody:/ {flag=1; next} flag')

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
      [[ "$breaking" =~ ^[yY]$ ]] && MESSAGE="${MESSAGE/:/:!}" || BODY=$(echo "$BODY" | sed 's/^## Breaking Changes.*/## Breaking Changes\nNone/')
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

gh pr create --base "$CURRENT_BRANCH" --head "$BRANCH_SANITIZED" --title "$MESSAGE" --body "$BODY"
echo "✅ PR created targeting $CURRENT_BRANCH from $BRANCH_SANITIZED"
