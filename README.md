gitaip: AI-Assisted Git Workflow Automation

gitaip is a powerful Git macro that streamlines your development workflow by automatically generating:
•	Branch names (semantic and descriptive)
•	Commit messages (conventional commits)
•	Pull Request descriptions (with optional structured templates)

All powered by the OpenAI API, tuned for software development productivity.

⸻

🔧 Setup Instructions

1. Run Setup Script

./start.sh

You will be prompted to:
•	Provide your OpenAI API key
•	Optionally store it in the macOS Keychain (if on macOS)
•	Register the gitaip command in your shell (e.g., .bashrc, .zshrc)

💡 After setup, reload your shell:

source ~/.zshrc  # or ~/.bashrc depending on your shell

2. Usage

git add . # or stage files manually
gitaip

The script will:
•	Detect staged changes or auto-stage modified files
•	Prompt OpenAI to generate a branch name, commit message, and PR body
•	Ask you to approve or refine them
•	Create the branch, commit, push, and open a GitHub PR

⸻

🧠 Features

✅ Semantic Commit Message and Branch Naming
•	Uses the diff (or changed files/functions if diff too large) to generate:
•	feat: ..., fix: ..., etc.
•	feat/add-validation, refactor/restructure-api, etc.

✅ PR Creation with AI-Generated Descriptions
•	Uses the GitHub CLI to create PRs
•	Option to use an advanced PR template (with sections like:
•	Issue being fixed
•	What was done
•	How it was tested
•	Breaking changes
•	Checklist
)

✅ Interactive Feedback Loop
•	Don’t like the suggestion? Provide feedback, and the AI will regenerate

✅ Merge Conflict Safety
•	Detects unresolved conflicts and exits cleanly

✅ Configurable Defaults
•	Remembers template preferences via .gitaipconfig
•	Adds .gitaipconfig to .gitignore automatically

⸻

📄 Example Output

📝 Proposed Branch: feat/validate-token-input
📝 Commit Message: feat: add validation for token input parsing
📝 PR Body:
## Issue being fixed or feature implemented
Token parsing was lenient, which allowed invalid inputs.

## What was done?
- Added strict input checks
- Updated the validator method in `token.rs`

## How Has This Been Tested?
- Added new unit tests in `tests/token_validation.rs`

## Breaking Changes
None

## Checklist:
- [x] I have performed a self-review of my own code
- [x] I have commented my code, particularly in hard-to-understand areas
- [x] I have added or updated relevant unit/integration/functional/e2e tests
- [ ] I have assigned this pull request to a milestone



⸻

🛠 Requirements
•	jq
•	curl
•	git
•	gh (GitHub CLI)

⸻

🔐 API Key Security
•	macOS: Securely stored in Keychain
•	Else: Stored in .bashrc/.zshrc with export OPENAI_API_KEY=...

⸻

🧪 Testing

You can simulate a run by staging some changes and running:

gitaip

Try changing a function, committing, and letting the AI generate the branch and PR.

⸻

🧹 Uninstalling

To remove the alias and API key:

# Remove alias and key from your shell config
nano ~/.zshrc  # or ~/.bashrc

# If stored in macOS Keychain
security delete-generic-password -s OPENAI_API_KEY -a $USER



⸻

📬 Contributions

PRs welcome. This tool is designed to accelerate productive Git workflows.

License

MIT