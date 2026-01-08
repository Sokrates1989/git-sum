#!/bin/bash
#
# Autostart management for git-sum (Bash)
#
# Description:
#   Handles macOS/Linux startup configuration for git-sum.

# Install autostart
install_autostart() {
    # Default to visible mode for backward compatibility
    install_autostart_visible
}

# Install autostart with visible terminal window
install_autostart_visible() {
    if [[ "$OSTYPE" == darwin* ]]; then
        install_autostart_macos_visible
    else
        install_autostart_linux
    fi
}

# Install autostart in background
install_autostart_background() {
    if [[ "$OSTYPE" == darwin* ]]; then
        install_autostart_macos_background
    else
        install_autostart_linux
    fi
}

# Install autostart with custom interval
install_autostart_custom() {
    echo ""
    echo "Choose interval:"
    echo "   1) Every 4 hours"
    echo "   2) Every 6 hours" 
    echo "   3) Every 12 hours"
    echo "   4) Every 24 hours (default)"
    echo "   5) Custom interval (hours)"
    echo "   q) Cancel"
    echo ""
    read -p "Choose interval: " interval_choice
    
    local interval_seconds
    case "$(echo "$interval_choice" | tr '[:upper:]' '[:lower:]')" in
        1)
            interval_seconds=14400  # 4 hours
            ;;
        2)
            interval_seconds=21600  # 6 hours
            ;;
        3)
            interval_seconds=43200  # 12 hours
            ;;
        4)
            interval_seconds=86400  # 24 hours
            ;;
        5)
            read -p "Enter interval in hours (1-168): " custom_hours
            if [[ "$custom_hours" =~ ^[0-9]+$ ]] && [[ "$custom_hours" -ge 1 ]] && [[ "$custom_hours" -le 168 ]]; then
                interval_seconds=$((custom_hours * 3600))
            else
                echo "Invalid interval. Using 24 hours."
                interval_seconds=86400
            fi
            ;;
        q)
            return
            ;;
        *)
            echo "Invalid choice. Using 24 hours."
            interval_seconds=86400
            ;;
    esac
    
    echo ""
    echo "Choose mode:"
    echo "   1) Visible terminal window"
    echo "   2) Background (silent)"
    echo ""
    read -p "Choose mode: " mode_choice
    
    if [[ "$(echo "$mode_choice" | tr '[:upper:]' '[:lower:]')" == "1" ]]; then
        if [[ "$OSTYPE" == darwin* ]]; then
            install_autostart_macos_visible_custom "$interval_seconds"
        else
            install_autostart_linux_custom "$interval_seconds"
        fi
    else
        if [[ "$OSTYPE" == darwin* ]]; then
            install_autostart_macos_background_custom "$interval_seconds"
        else
            install_autostart_linux_custom "$interval_seconds"
        fi
    fi
}

# Get current autostart interval
get_autostart_interval() {
    if [[ "$OSTYPE" == darwin* ]]; then
        local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
        if [[ -f "$plist_path" ]]; then
            local interval
            interval=$(plutil -extract StartInterval integer "$plist_path" 2>/dev/null || echo "")
            if [[ -n "$interval" ]]; then
                local hours=$((interval / 3600))
                if [[ $hours -eq 1 ]]; then
                    echo "Every hour"
                elif [[ $hours -lt 24 ]]; then
                    echo "Every $hours hours"
                elif [[ $hours -eq 24 ]]; then
                    echo "Every 24 hours"
                elif [[ $hours -gt 24 ]]; then
                    echo "Every $hours hours"
                fi
            fi
        fi
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

install_autostart_macos_visible() {
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
        <string>/usr/bin/osascript</string>
        <string>-e</string>
        <string>tell application "Terminal" to do script "/bin/bash ${script_path}; sleep 5; exit"</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>86400</integer>
</dict>
</plist>
EOF
    
    launchctl load "$plist_path" 2>/dev/null || true
    
    echo "[OK] Added git-sum to macOS Login Items"
    echo "   Location: $plist_path"
    echo "   Note: Will open in Terminal window and auto-close after 5 seconds"
}

install_autostart_macos_background() {
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
    
    echo "[OK] Added git-sum to macOS Login Items"
    echo "   Location: $plist_path"
    echo "   Note: Will run in background (logs: /tmp/git-sum.log)"
}

uninstall_autostart_macos() {
    local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    
    if [[ -f "$plist_path" ]]; then
        launchctl unload "$plist_path" 2>/dev/null || true
        rm -f "$plist_path"
        echo "[OK] Removed git-sum from macOS Login Items"
    else
        echo "[i] git-sum was not in startup"
    fi
}

is_autostart_installed_macos() {
    local plist_path="$HOME/Library/LaunchAgents/com.gitsum.agent.plist"
    [[ -f "$plist_path" ]]
}

# Custom interval variants for macOS
install_autostart_macos_visible_custom() {
    local interval_seconds=$1
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
        <string>/usr/bin/osascript</string>
        <string>-e</string>
        <string>tell application "Terminal" to do script "/bin/bash ${script_path}; sleep 5; exit"</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>${interval_seconds}</integer>
</dict>
</plist>
EOF
    
    launchctl load "$plist_path" 2>/dev/null || true
    
    local hours=$((interval_seconds / 3600))
    echo "[OK] Added git-sum to macOS Login Items"
    echo "   Location: $plist_path"
    echo "   Interval: Every $hours hours"
    echo "   Note: Will open in Terminal window and auto-close after 5 seconds"
}

install_autostart_macos_background_custom() {
    local interval_seconds=$1
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
    <integer>${interval_seconds}</integer>
    <key>StandardOutPath</key>
    <string>/tmp/git-sum.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/git-sum.error.log</string>
</dict>
</plist>
EOF
    
    launchctl load "$plist_path" 2>/dev/null || true
    
    local hours=$((interval_seconds / 3600))
    echo "[OK] Added git-sum to macOS Login Items"
    echo "   Location: $plist_path"
    echo "   Interval: Every $hours hours"
    echo "   Note: Will run in background (logs: /tmp/git-sum.log)"
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
    
    echo "[OK] Added git-sum to Linux autostart"
    echo "   Location: $desktop_file"
}

uninstall_autostart_linux() {
    local desktop_file="$HOME/.config/autostart/git-sum.desktop"
    
    if [[ -f "$desktop_file" ]]; then
        rm -f "$desktop_file"
        echo "[OK] Removed git-sum from Linux autostart"
    else
        echo "[i] git-sum was not in startup"
    fi
}

is_autostart_installed_linux() {
    local desktop_file="$HOME/.config/autostart/git-sum.desktop"
    [[ -f "$desktop_file" ]]
}

# Custom interval variants for Linux
install_autostart_linux_custom() {
    local interval_seconds=$1
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/git-sum.desktop"
    local script_path="${ROOT_DIR}/git-sum.sh"
    
    mkdir -p "$autostart_dir"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=git-sum
Comment=Git Repository Status Summary
Exec=/bin/bash -c "while true; do ${script_path}; sleep ${interval_seconds}; done"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Terminal=true
EOF
    
    chmod +x "$desktop_file"
    
    local hours=$((interval_seconds / 3600))
    echo "[OK] Added git-sum to Linux autostart"
    echo "   Location: $desktop_file"
    echo "   Interval: Every $hours hours"
}

# Interactive autostart configuration
run_autostart_config() {
    local is_installed
    is_installed=$(is_autostart_installed && echo "true" || echo "false")
    
    echo ""
    echo "[*] Autostart Configuration"
    echo "=========================="
    echo ""
    
    if [[ "$is_installed" == "true" ]]; then
        echo "   Status: [OK] Enabled"
        echo "   git-sum will run when you log in."
        # Show current interval if we can detect it
        local current_interval
        current_interval=$(get_autostart_interval)
        if [[ -n "$current_interval" ]]; then
            echo "   Current interval: $current_interval"
        fi
    else
        echo "   Status: [X] Disabled"
        echo "   git-sum will not run automatically."
    fi
    
    echo ""
    echo "Options:"
    
    if [[ "$is_installed" == "true" ]]; then
        echo "   1) Disable autostart"
        echo "   2) Reconfigure (visible/background/interval)"
        echo "   3) Run once now"
    else
        echo "   1) Enable autostart (visible terminal)"
        echo "   2) Enable autostart (background)"
        echo "   3) Enable autostart (custom interval)"
    fi
    echo "   q) Back"
    echo ""
    
    read -p "Choose option: " choice
    
    case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
        1)
            if [[ "$is_installed" == "true" ]]; then
                set_autostart "false"
                uninstall_autostart
            else
                set_autostart "true"
                install_autostart_visible
            fi
            ;;
        2)
            if [[ "$is_installed" == "true" ]]; then
                echo ""
                echo "Choose autostart mode:"
                echo "   1) Visible terminal window"
                echo "   2) Background (silent)"
                echo "   3) Custom interval"
                echo "   q) Cancel"
                echo ""
                read -p "Choose mode: " mode_choice
                case "$(echo "$mode_choice" | tr '[:upper:]' '[:lower:]')" in
                    1)
                        uninstall_autostart
                        install_autostart_visible
                        ;;
                    2)
                        uninstall_autostart
                        install_autostart_background
                        ;;
                    3)
                        uninstall_autostart
                        install_autostart_custom
                        ;;
                    q)
                        return
                        ;;
                    *)
                        echo "Invalid choice."
                        ;;
                esac
            else
                set_autostart "true"
                install_autostart_background
            fi
            ;;
        3)
            if [[ "$is_installed" == "true" ]]; then
                echo ""
                echo "Running git-sum once now..."
                "${ROOT_DIR}/git-sum.sh"
            else
                set_autostart "true"
                install_autostart_custom
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
