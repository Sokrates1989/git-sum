#!/bin/bash
#
# git-sum - Git Repository Status Summary Tool for macOS/Linux
#
# Description:
#   Scans configured directories for git repositories and provides a summary of their states.
#   Automatically pulls changes when safe, and offers solutions for repos with issues.
#
# Usage:
#   git-sum              Normal run - check all repos and pull if safe
#   git-sum -a           Add more folders to watch (--add)
#   git-sum -s           Dry run - show status without pulling (--status)
#   git-sum -c           Open configuration editor (--config)
#   git-sum -as          Configure autostart settings (--autostart)
#   git-sum -u           Update to latest version (--update)
#   git-sum -h           Show help (--help)
#
# Author: Sokrates1989
# Version: 1.0.0

set -e

# === Script paths ===
SCRIPT_PATH="$(realpath "$0")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_DIR="${ROOT_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/watched-folders.json"
MODULES_DIR="${ROOT_DIR}/modules"

# === Source modules ===
source "${MODULES_DIR}/config-manager.sh"
source "${MODULES_DIR}/git-operations.sh"
source "${MODULES_DIR}/first-time-setup.sh"
source "${MODULES_DIR}/ui-helpers.sh"
source "${MODULES_DIR}/autostart-manager.sh"

# === Variables ===
MODE="run"
DRY_RUN=false

# === Functions ===

show_help() {
    echo ""
    echo "[*] git-sum - Git Repository Status Summary Tool"
    echo "================================================"
    echo ""
    echo "Usage:"
    echo "  git-sum              Normal run - check all repos and pull if safe"
    echo "  git-sum -a           Add more folders to watch (--add)"
    echo "  git-sum -s           Dry run - show status without pulling (--status)"
    echo "  git-sum -c           Open configuration editor (--config)"
    echo "  git-sum -as          Configure autostart settings (--autostart)"
    echo "  git-sum -u           Update to latest version (--update)"
    echo "  git-sum -h           Show this help (--help)"
    echo ""
    echo "Description:"
    echo "  Scans configured directories for git repositories and provides"
    echo "  a summary of their states. Automatically pulls changes when safe,"
    echo "  and offers solutions for repos that need attention."
    echo ""
}

run_update() {
    echo ""
    echo "[*] Checking for updates..."
    
    cd "${ROOT_DIR}"
    
    local status
    status=$(run_git_command status --porcelain 2>/dev/null || echo "")
    if [[ -n "$status" ]]; then
        echo "[!] Local changes detected. Please commit or stash them first."
        return
    fi
    
    run_git_command fetch origin &>/dev/null || true
    local behind
    behind=$(run_git_command rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
    
    if [[ "$behind" -gt 0 ]]; then
        echo "[>] Updating git-sum ($behind commits behind)..."
        if run_git_command pull --ff-only &>/dev/null; then
            echo "[OK] Updated successfully!"
        else
            echo "[X] Update failed during pull."
        fi
    else
        echo "[OK] Already up to date."
    fi
}

check_first_time_setup() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo ""
        echo "[*] Welcome to git-sum!"
        echo "   It looks like this is your first time running git-sum."
        echo ""
        run_first_time_setup
        return $?
    fi
    
    local folder_count
    folder_count=$(get_folder_count)
    if [[ "$folder_count" -eq 0 ]]; then
        echo ""
        echo "[!] No folders configured yet."
        echo ""
        run_first_time_setup
        return $?
    fi
    
    return 0
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--add)
            MODE="add"
            shift
            ;;
        -s|--status)
            DRY_RUN=true
            shift
            ;;
        -c|--config)
            MODE="config"
            shift
            ;;
        -as|--autostart)
            MODE="autostart"
            shift
            ;;
        -u|--update)
            MODE="update"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "[X] Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# === Ensure config directory exists ===
mkdir -p "${CONFIG_DIR}"

# === Main logic ===
case "$MODE" in
    update)
        run_update
        exit 0
        ;;
    add)
        if ! check_first_time_setup; then
            exit 0
        fi
        run_add_folders
        exit 0
        ;;
    config)
        run_config_editor
        exit 0
        ;;
    autostart)
        run_autostart_config
        exit 0
        ;;
    run)
        if ! check_first_time_setup; then
            exit 0
        fi
        
        echo ""
        echo "[*] git-sum - Scanning repositories..."
        echo "======================================"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "   (Dry run mode - no changes will be made)"
        fi
        
        echo ""
        
        # Get all repos and check their status
        run_repo_scan "$DRY_RUN"
        
        # Display summary
        show_summary "$DRY_RUN"
        ;;
esac
