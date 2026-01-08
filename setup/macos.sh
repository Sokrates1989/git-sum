#!/usr/bin/env bash
#
# macOS setup script for git-sum
#
# Description:
#   Downloads and installs git-sum, creates global command, and runs first-time setup.
#
# Usage:
#   bash macos.sh

set -e

TARGET_DIR="$HOME/tools/git-sum"
REPO_URL="https://github.com/Sokrates1989/git-sum.git"

echo ""
echo "🔄 git-sum Installer"
echo "===================="
echo ""
echo "➡️ Installing git-sum into $TARGET_DIR"

# Step 1: Clone or update the repository
if [[ ! -d "$TARGET_DIR/.git" ]]; then
    echo "Cloning repository..."
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    git clone "$REPO_URL" .
else
    echo "ℹ️ git-sum already cloned – attempting to update..."
    cd "$TARGET_DIR"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git pull --ff-only || echo "⚠️ Could not fast-forward; continuing with existing clone."
    fi
fi

# Step 2: Make scripts executable
chmod +x "$TARGET_DIR/git-sum.sh"
chmod +x "$TARGET_DIR/install.sh"
chmod +x "$TARGET_DIR/modules/"*.sh 2>/dev/null || true

# Step 3: Run the installer
echo ""
echo "🔐 The installer will now set up git-sum."
echo "   You may be prompted for your password to create the global 'git-sum' command."
echo ""

bash "$TARGET_DIR/install.sh"

echo ""
echo "✅ Installation complete!"
