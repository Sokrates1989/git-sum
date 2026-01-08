#!/bin/bash
#
# Uninstall script for git-sum (macOS/Linux)
#
# Description:
#   Removes git-sum installation, symlinks, and autostart entries.

set -e

echo ""
echo "🗑️  git-sum Uninstaller"
echo "======================="
echo ""

# Determine install location
INSTALL_DIR="$HOME/tools/git-sum"

echo "This will remove:"
echo "  - git-sum command from PATH"
echo "  - Installation directory: $INSTALL_DIR"
echo "  - Autostart entries (if configured)"
echo ""

read -p "Continue with uninstall? (y/N): " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Remove symlinks
echo ""
echo "Removing symlinks..."

if [[ -L "/usr/local/bin/git-sum" ]]; then
    sudo rm -f "/usr/local/bin/git-sum" 2>/dev/null || rm -f "/usr/local/bin/git-sum"
    echo "  ✅ Removed /usr/local/bin/git-sum"
fi

if [[ -L "$HOME/.local/bin/git-sum" ]]; then
    rm -f "$HOME/.local/bin/git-sum"
    echo "  ✅ Removed ~/.local/bin/git-sum"
fi

# Remove autostart (macOS)
if [[ "$OSTYPE" == darwin* ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        echo "  ✅ Removed macOS autostart"
    fi
    
    # Remove Desktop shortcut
    if [[ -f "$HOME/Desktop/git-sum.command" ]]; then
        rm -f "$HOME/Desktop/git-sum.command"
        echo "  ✅ Removed Desktop shortcut"
    fi
fi

# Remove autostart (Linux)
if [[ -f "$HOME/.config/autostart/git-sum.desktop" ]]; then
    rm -f "$HOME/.config/autostart/git-sum.desktop"
    echo "  ✅ Removed Linux autostart"
fi

# Remove installation directory
echo ""
echo "Removing installation directory..."

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  ✅ Removed $INSTALL_DIR"
else
    echo "  ℹ️  Directory not found: $INSTALL_DIR"
fi

# Clean up empty parent directory
if [[ -d "$HOME/tools" ]] && [[ -z "$(ls -A "$HOME/tools" 2>/dev/null)" ]]; then
    rmdir "$HOME/tools" 2>/dev/null || true
    echo "  ✅ Removed empty ~/tools directory"
fi

echo ""
echo "✅ git-sum has been uninstalled."
echo ""
echo "Note: You may need to remove PATH entries from your shell config"
echo "      (~/.bashrc, ~/.zshrc) if they were added manually."
echo ""
