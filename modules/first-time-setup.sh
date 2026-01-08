#!/bin/bash
#
# First-time setup wizard for git-sum (Bash)
#
# Description:
#   Guides users through initial configuration including folder selection and autostart setup.

# Run first-time setup wizard
run_first_time_setup() {
    echo "[*] First-Time Setup"
    echo "==================="
    echo ""
    echo "git-sum scans directories containing git repositories and helps"
    echo "keep them all up to date. Let's add some folders to watch."
    echo ""
    
    # Add folders
    if ! run_add_folders; then
        echo ""
        echo "[!] No folders were added. Run 'git-sum -a' later to add folders."
        return 1
    fi
    
    # Ask about autostart
    echo ""
    echo "[*] Autostart Configuration"
    echo "--------------------------"
    echo ""
    echo "Would you like git-sum to run automatically when you log in?"
    echo "This helps ensure your repos are always up to date."
    echo ""
    
    read -p "Enable autostart? (y/N) " autostart_choice
    
    if [[ "$(echo "$autostart_choice" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
        set_autostart "true"
        install_autostart
        echo "[OK] Autostart enabled!"
    else
        echo "[i] Autostart not enabled. You can enable it later with 'git-sum -as'"
    fi
    
    echo ""
    echo "[OK] Setup complete!"
    echo ""
    echo "You can now run:"
    echo "   git-sum          - Check all repos and pull if safe"
    echo "   git-sum -s       - Show status without pulling"
    echo "   git-sum -a       - Add more folders"
    echo "   git-sum -h       - Show help"
    echo ""
    
    return 0
}

# Add folders interactively
run_add_folders() {
    local single_folder=${1:-false}
    local folders_added=0
    
    echo ""
    echo "[>] Add Folders to Watch"
    echo "-----------------------"
    echo ""
    echo "Select folders that CONTAIN git repositories."
    echo "(e.g., '/Users/name/Projects' if you have repos like '.../Projects/my-repo')"
    echo ""
    
    local continue_adding=true
    while [[ "$continue_adding" == true ]]; do
        echo ""
        echo "Options:"
        echo "   1) Browse for folder (if supported)"
        echo "   2) Enter path manually"
        echo "   q) Done adding folders"
        echo ""
        
        read -p "Choose option: " choice
        
        case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
            1)
                local folder
                folder=$(select_folder_dialog)
                if [[ -n "$folder" ]]; then
                    if add_watched_folder "$folder"; then
                        ((folders_added++))
                        show_folder_preview "$folder"
                    fi
                else
                    echo "[i] No folder selected."
                fi
                ;;
            2)
                read -p "Enter folder path: " path
                if [[ -n "$path" ]]; then
                    # Expand ~ to home directory
                    local expanded_path
                    expanded_path=$(eval echo "$path")
                    if add_watched_folder "$expanded_path"; then
                        ((folders_added++))
                        show_folder_preview "$expanded_path"
                    fi
                fi
                ;;
            q)
                continue_adding=false
                ;;
            *)
                echo "Invalid choice."
                ;;
        esac
        
        if [[ "$single_folder" == true ]] && [[ "$folders_added" -gt 0 ]]; then
            continue_adding=false
        fi
    done
    
    [[ "$folders_added" -gt 0 ]]
}

# Open folder picker dialog (platform-specific)
select_folder_dialog() {
    local selected_folder=""
    
    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: Use osascript
        selected_folder=$(osascript -e 'tell application "Finder"
            activate
            set folderPath to choose folder with prompt "Select a folder containing git repositories"
            return POSIX path of folderPath
        end tell' 2>/dev/null)
    elif command -v zenity &>/dev/null; then
        # Linux with zenity
        selected_folder=$(zenity --file-selection --directory --title="Select a folder containing git repositories" 2>/dev/null)
    elif command -v kdialog &>/dev/null; then
        # Linux with kdialog (KDE)
        selected_folder=$(kdialog --getexistingdirectory "$HOME" --title "Select a folder containing git repositories" 2>/dev/null)
    else
        # Fallback: just ask for manual input
        echo "[i] No graphical file picker available. Please enter path manually." >&2
        return 1
    fi
    
    # Remove trailing slash if present
    selected_folder="${selected_folder%/}"
    
    echo "$selected_folder"
}

# Show preview of repos in a folder
show_folder_preview() {
    local folder_path=$1
    
    echo ""
    echo "   Found repositories:"
    
    local repo_count=0
    local max_show=5
    
    for subdir in "$folder_path"/*/; do
        [[ ! -d "$subdir" ]] && continue
        
        if [[ -d "${subdir}.git" ]]; then
            ((repo_count++))
            if [[ "$repo_count" -le "$max_show" ]]; then
                local repo_name
                repo_name=$(basename "${subdir%/}")
                echo "      [*] $repo_name"
            fi
        fi
    done
    
    if [[ "$repo_count" -gt "$max_show" ]]; then
        echo "      ... and $((repo_count - max_show)) more"
    fi
    
    if [[ "$repo_count" -eq 0 ]]; then
        echo "      (no git repositories found in first level)"
    else
        echo "      Total: $repo_count repositories"
    fi
}
