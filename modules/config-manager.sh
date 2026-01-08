#!/bin/bash
#
# Configuration management for git-sum (Bash)
#
# Description:
#   Handles reading, writing, and managing the watched folders configuration.

# Get watched folders from config file
get_watched_folders() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "[]"
        return
    fi
    
    # Extract folders array from JSON
    if command -v jq &>/dev/null; then
        jq -r '.folders // []' "$CONFIG_FILE" 2>/dev/null || echo "[]"
    else
        # Fallback: simple grep-based extraction
        grep -o '"folders":\s*\[[^]]*\]' "$CONFIG_FILE" 2>/dev/null | sed 's/"folders":\s*//' || echo "[]"
    fi
}

# Get the count of watched folders
get_folder_count() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "0"
        return
    fi
    
    if command -v jq &>/dev/null; then
        jq -r '.folders | length' "$CONFIG_FILE" 2>/dev/null || echo "0"
    else
        # Fallback: count lines with paths
        local count
        count=$(grep -c '"/' "$CONFIG_FILE" 2>/dev/null || echo "0")
        echo "$count"
    fi
}

# Get folder at specific index (0-based)
get_folder_at_index() {
    local index=$1
    
    if command -v jq &>/dev/null; then
        jq -r ".folders[$index] // empty" "$CONFIG_FILE" 2>/dev/null
    else
        # Fallback
        echo ""
    fi
}

# Get all folders as newline-separated list
get_all_folders() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi
    
    if command -v jq &>/dev/null; then
        jq -r '.folders[]' "$CONFIG_FILE" 2>/dev/null
    else
        # Fallback: extract paths between quotes
        grep -o '"/[^"]*"' "$CONFIG_FILE" 2>/dev/null | tr -d '"' | grep -v '^$'
    fi
}

# Check if autostart is enabled
is_autostart_enabled() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "false"
        return
    fi
    
    if command -v jq &>/dev/null; then
        jq -r '.settings.autostart // false' "$CONFIG_FILE" 2>/dev/null
    else
        echo "false"
    fi
}

# Save configuration
save_config() {
    local folders_json=$1
    local autostart=${2:-false}
    local last_run
    last_run=$(date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")
    
    mkdir -p "${CONFIG_DIR}"
    
    cat > "$CONFIG_FILE" << EOF
{
  "folders": $folders_json,
  "settings": {
    "autostart": $autostart,
    "lastRun": "$last_run"
  }
}
EOF
}

# Add a folder to watched list
add_watched_folder() {
    local folder_path=$1
    
    # Validate folder exists
    if [[ ! -d "$folder_path" ]]; then
        echo "[X] Folder does not exist: $folder_path"
        return 1
    fi
    
    # Normalize path
    local normalized_path
    normalized_path=$(cd "$folder_path" && pwd)
    
    # Get current config
    local current_folders autostart
    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        current_folders=$(jq -r '.folders // []' "$CONFIG_FILE")
        autostart=$(jq -r '.settings.autostart // false' "$CONFIG_FILE")
        
        # Check if already exists
        if jq -e ".folders | index(\"$normalized_path\")" "$CONFIG_FILE" &>/dev/null; then
            echo "[i] Folder already in watch list: $normalized_path"
            return 1
        fi
        
        # Add new folder
        local new_folders
        new_folders=$(echo "$current_folders" | jq ". + [\"$normalized_path\"]")
        save_config "$new_folders" "$autostart"
    else
        # Simple case: create new config
        save_config "[\"$normalized_path\"]" "false"
    fi
    
    echo "[OK] Added folder: $normalized_path"
    return 0
}

# Remove a folder from watched list
remove_watched_folder() {
    local folder_path=$1
    
    if [[ ! -f "$CONFIG_FILE" ]] || ! command -v jq &>/dev/null; then
        echo "[i] No config file or jq not available"
        return 1
    fi
    
    local autostart
    autostart=$(jq -r '.settings.autostart // false' "$CONFIG_FILE")
    
    # Remove folder
    local new_folders
    new_folders=$(jq ".folders | map(select(. != \"$folder_path\"))" "$CONFIG_FILE")
    
    save_config "$new_folders" "$autostart"
    echo "[OK] Removed folder: $folder_path"
    return 0
}

# Interactive config editor
run_config_editor() {
    while true; do
        echo ""
        echo "[*] git-sum Configuration"
        echo "========================="
        echo ""
        echo "Current watched folders:"
        
        local folder_count
        folder_count=$(get_folder_count)
        
        if [[ "$folder_count" -eq 0 ]]; then
            echo "   (none)"
        else
            local index=1
            while IFS= read -r folder; do
                if [[ -d "$folder" ]]; then
                    echo "   $index) $folder [OK]"
                else
                    echo "   $index) $folder [X] (not found)"
                fi
                ((index++))
            done < <(get_all_folders)
        fi
        
        local autostart_status
        autostart_status=$(is_autostart_enabled)
        
        echo ""
        echo "Options:"
        echo "   a) Add folder"
        echo "   r) Remove folder"
        echo "   s) Toggle autostart (currently: $autostart_status)"
        echo "   q) Back to main"
        echo ""
        
        read -p "Enter choice: " choice
        
        case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
            a)
                run_add_folders true
                ;;
            r)
                if [[ "$folder_count" -eq 0 ]]; then
                    echo "No folders to remove."
                else
                    read -p "Enter folder number to remove (or 'c' to cancel): " remove_index
                    if [[ "$remove_index" != "c" ]]; then
                        local idx=$((remove_index - 1))
                        local folder_to_remove
                        folder_to_remove=$(get_folder_at_index "$idx")
                        if [[ -n "$folder_to_remove" ]]; then
                            remove_watched_folder "$folder_to_remove"
                        else
                            echo "Invalid selection."
                        fi
                    fi
                fi
                ;;
            s)
                local current_autostart
                current_autostart=$(is_autostart_enabled)
                if [[ "$current_autostart" == "true" ]]; then
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
    done
}

# Set autostart value in config
set_autostart() {
    local value=$1
    
    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        local folders
        folders=$(jq -r '.folders // []' "$CONFIG_FILE")
        save_config "$folders" "$value"
    fi
}
