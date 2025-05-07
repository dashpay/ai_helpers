#!/bin/bash

echo "Welcome to aip setup"
read -p "Enter your OpenAI API key: " OPENAI_API_KEY

# Inject the API key into aip.sh
AIP_SCRIPT="git_commands/gitaip.sh"

if [[ ! -f "$AIP_SCRIPT" ]]; then
  echo "Error: $AIP_SCRIPT not found"
  exit 1
fi

# Validate the API key with OpenAI
echo "Validating OpenAI API key..."

VALIDATION_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY")

if [[ "$VALIDATION_RESPONSE" -ne 200 ]]; then
  echo "❌ Invalid OpenAI API key or network error (HTTP $VALIDATION_RESPONSE)."
  exit 1
fi

echo "✅ OpenAI API key validated successfully."

chmod +x "$AIP_SCRIPT"

# Detect OS
OS_TYPE=$(uname)
echo "Detected OS: $OS_TYPE"

# Detect shell config
if [[ "$SHELL" == *zsh ]]; then
  SHELL_CONFIG="$HOME/.zshrc"
elif [[ "$SHELL" == *bash ]]; then
  SHELL_CONFIG="$HOME/.bashrc"
else
  echo "Unsupported shell. Please manually add the alias to your shell config."
  exit 1
fi

# Offer macOS Keychain integration
if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "Would you like to store your API key securely in macOS Keychain? [Y/n]"
  read -r use_keychain
  if [[ "$use_keychain" =~ ^[Yy]$ || -z "$use_keychain" ]]; then
    security add-generic-password -a "$USER" -s "OPENAI_API_KEY" -w "$OPENAI_API_KEY" -U
    KEYCHAIN_SNIPPET='export OPENAI_API_KEY="$(security find-generic-password -a "$USER" -s "OPENAI_API_KEY" -w)"'
  else
    KEYCHAIN_SNIPPET="export OPENAI_API_KEY=\"$OPENAI_API_KEY\""
  fi
else
  KEYCHAIN_SNIPPET="export OPENAI_API_KEY=\"$OPENAI_API_KEY\""
fi

# Insert or replace OPENAI_API_KEY
if grep -q "OPENAI_API_KEY" "$SHELL_CONFIG"; then
  sed -i.bak '/OPENAI_API_KEY/d' "$SHELL_CONFIG"
fi
echo "$KEYCHAIN_SNIPPET" >> "$SHELL_CONFIG"
echo "OPENAI_API_KEY registered in $SHELL_CONFIG."

# Check if alias is already present
if grep -q "alias aip=" "$SHELL_CONFIG"; then
  echo "Existing 'aip' alias found in $SHELL_CONFIG."
  read -p "Do you want to update it? [y/N] " choice
  case "$choice" in
    y|Y )
      sed -i.bak "/alias aip=/d" "$SHELL_CONFIG"
      ;;
    * )
      echo "Leaving existing alias unchanged."
      exit 0
      ;;
  esac
fi

# Register alias
echo "alias aip='bash $(pwd)/$AIP_SCRIPT'" >> "$SHELL_CONFIG"
echo "aip alias registered in $SHELL_CONFIG."

# Advise to reload shell
echo "To apply changes, run:"
echo "  source $SHELL_CONFIG"
