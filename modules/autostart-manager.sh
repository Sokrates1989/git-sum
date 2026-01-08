#!/bin/bash
#
# Autostart management for git-sum (Bash)
#
# Description:
#   Handles macOS/Linux startup configuration for git-sum.

# Install autostart
install_autostart() {
    if [[ "$OSTYPE" == darwin* ]]; then
        install_autostart_macos
    else
        install_autostart_linux
    fi
}

# Uninstall autostart
uninstall_autostart() {
    if [[ "$OSTYPE" == darwin* ]]; then
        uninstall_autostart_macos
    else
        uninstall_autostart_linux
    fi
}

# Check if autostart is installed
is_autostart_installed() {
    if [[ "$OSTYPE" == darwin* ]]; then
        is_autostart_installed_macos
    else
        is_autostart_installed_linux
    fi
}

# === macOS Implementation ===

install_autostart_macos() {
    local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    local script_path="${ROOT_DIR}/git-sum.sh"
    
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gitsum.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>86400</integer>
    <key>StandardOutPath</key>
    <string>/tmp/git-sum.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/git-sum.error.log</string>
</dict>
</plist>
EOF
    
    launchctl load "$plist_path" 2>/dev/null || true
    
    echo "✅ Added git-sum to macOS Login Items"
    echo "   Location: $plist_path"
}

uninstall_autostart_macos() {
    local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    
    if [[ -f "$plist_path" ]]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        echo "✅ Removed git-sum from macOS Login Items"
    else
        echo "ℹ️  git-sum was not in startup"
    fi
}

is_autostart_installed_macos() {
    local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    [[ -f "$plist_path" ]]
}

# === Linux Implementation ===

install_autostart_linux() {
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/git-sum.desktop"
    local script_path="${ROOT_DIR}/git-sum.sh"
    
    mkdir -p "$autostart_dir"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Name=git-sum
Comment=Git Repository Status Summary
Exec=/bin/bash "${script_path}"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Terminal=true
EOF
    
    chmod +x "$desktop_file"
    
    echo "✅ Added git-sum to Linux autostart"
    echo "   Location: $desktop_file"
}

uninstall_autostart_linux() {
    local desktop_file="$HOME/.config/autostart/git-sum.desktop"
    
    if [[ -f "$desktop_file" ]]; then
        rm -f "$desktop_file"
        echo "✅ Removed git-sum from Linux autostart"
    else
        echo "ℹ️  git-sum was not in startup"
    fi
}

is_autostart_installed_linux() {
    local desktop_file="$HOME/.config/autostart/git-sum.desktop"
    [[ -f "$desktop_file" ]]
}

# Interactive autostart configuration
run_autostart_config() {
    local is_installed
    is_installed=$(is_autostart_installed && echo "true" || echo "false")
    
    echo ""
    echo "⏰ Autostart Configuration"
    echo "=========================="
    echo ""
    
    if [[ "$is_installed" == "true" ]]; then
        echo "   Status: ✅ Enabled"
        echo "   git-sum will run when you log in."
    else
        echo "   Status: ❌ Disabled"
        echo "   git-sum will not run automatically."
    fi
    
    echo ""
    echo "Options:"
    
    if [[ "$is_installed" == "true" ]]; then
        echo "   1) Disable autostart"
    else
        echo "   1) Enable autostart"
    fi
    echo "   q) Back"
    echo ""
    
    read -p "Choose option: " choice
    
    case "${choice,,}" in
        1)
            if [[ "$is_installed" == "true" ]]; then
                set_autostart "false"
                uninstall_autostart
            else
                set_autostart "true"
                install_autostart
            fi
            ;;
        q)
            return
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
}
