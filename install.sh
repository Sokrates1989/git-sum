#!/bin/bash
#
# Unix installer for git-sum (macOS/Linux)
#
# Description:
#   Creates global 'git-sum' command and optionally runs first-time setup.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_SUM_SCRIPT="${SCRIPT_DIR}/git-sum.sh"

echo ""
echo "🔄 git-sum Installer"
echo "===================="
echo ""
echo "[INFO] Installing git-sum..."

# Step 1: Make scripts executable
chmod +x "${GIT_SUM_SCRIPT}"
chmod +x "${SCRIPT_DIR}/modules/"*.sh 2>/dev/null || true

# Step 2: Ensure config directory exists
mkdir -p "${SCRIPT_DIR}/config"

# Step 3: Create symlink in /usr/local/bin or ~/.local/bin
BIN_DIR=""
NEEDS_SUDO=false

if [[ -w "/usr/local/bin" ]]; then
    BIN_DIR="/usr/local/bin"
elif [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    BIN_DIR="$HOME/.local/bin"
else
    # Try /usr/local/bin with sudo
    BIN_DIR="/usr/local/bin"
    NEEDS_SUDO=true
fi

echo ""
echo "Creating 'git-sum' command in ${BIN_DIR}..."

if [[ "$NEEDS_SUDO" == true ]]; then
    echo "🔐 This requires administrator privileges."
    sudo ln -sf "${GIT_SUM_SCRIPT}" "${BIN_DIR}/git-sum"
else
    ln -sf "${GIT_SUM_SCRIPT}" "${BIN_DIR}/git-sum"
fi

echo "✅ Created 'git-sum' command in ${BIN_DIR}"

# Step 4: Add ~/.local/bin to PATH if needed
if [[ "$BIN_DIR" == "$HOME/.local/bin" ]]; then
    CURRENT_SHELL=$(basename "$SHELL")
    EXPORT_LINE='export PATH="$HOME/.local/bin:$PATH"'
    SHELL_RC=""
    
    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
        SHELL_RC="$HOME/.bashrc"
    fi
    
    if [[ -n "$SHELL_RC" && -f "$SHELL_RC" ]]; then
        if ! grep -Fxq "$EXPORT_LINE" "$SHELL_RC"; then
            echo "$EXPORT_LINE" >> "$SHELL_RC"
            echo "✅ Added PATH update to $SHELL_RC"
            echo "   Run: source $SHELL_RC"
        else
            echo "ℹ️  PATH already set in $SHELL_RC"
        fi
    fi
fi

# Step 5: Create Desktop shortcut (optional, macOS only)
if [[ "$OSTYPE" == darwin* ]]; then
    echo ""
    read -p "Create Desktop shortcut? (y/N): " create_shortcut
    if [[ "${create_shortcut,,}" == "y" ]]; then
        DESKTOP_DIR="$HOME/Desktop"
        COMMAND_FILE="${DESKTOP_DIR}/git-sum.command"
        
        cat > "${COMMAND_FILE}" << EOF
#!/bin/bash
"${GIT_SUM_SCRIPT}" "\$@"
EOF
        chmod +x "${COMMAND_FILE}"
        echo "✅ Created Desktop shortcut: git-sum.command"
    fi
fi

echo ""
echo "==============================================================="
echo "✅ Installation complete!"
echo ""
echo "Usage (after restarting terminal or sourcing shell config):"
echo "  git-sum           - Check all repos and pull if safe"
echo "  git-sum -s        - Show status without pulling (dry run)"
echo "  git-sum -a        - Add more folders to watch"
echo "  git-sum -c        - Open configuration editor"
echo "  git-sum -h        - Show help"
echo ""
echo "First run will guide you through initial setup."
echo "==============================================================="
