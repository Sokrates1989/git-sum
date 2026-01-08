#!/bin/bash
#
# Git operations for git-sum (Bash)
#
# Description:
#   Handles git repository scanning, status checking, and safe pulling.

# Global arrays to store results
declare -a REPO_RESULTS
declare -a REPO_NAMES
declare -a REPO_PATHS
declare -a REPO_STATUSES
declare -a REPO_MESSAGES
declare -a REPO_BRANCHES
declare -a REPO_CAN_PULL

# Reset results arrays
reset_results() {
    REPO_RESULTS=()
    REPO_NAMES=()
    REPO_PATHS=()
    REPO_STATUSES=()
    REPO_MESSAGES=()
    REPO_BRANCHES=()
    REPO_CAN_PULL=()
}

# Get repo status
get_repo_status() {
    local repo_path=$1
    local index=${#REPO_NAMES[@]}
    
    REPO_PATHS[$index]="$repo_path"
    REPO_NAMES[$index]=$(basename "$repo_path")
    REPO_STATUSES[$index]="unknown"
    REPO_MESSAGES[$index]=""
    REPO_BRANCHES[$index]=""
    REPO_CAN_PULL[$index]="false"
    
    cd "$repo_path" || return 1
    
    # Check if it's a git repo
    if ! git rev-parse --git-dir &>/dev/null; then
        REPO_STATUSES[$index]="not_git"
        REPO_MESSAGES[$index]="Not a git repository"
        return 0
    fi
    
    # Get current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$current_branch" ]]; then
        current_branch="(detached)"
    fi
    REPO_BRANCHES[$index]="$current_branch"
    
    # Check for uncommitted changes
    local status has_changes=false has_untracked=false
    status=$(git status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        if echo "$status" | grep -q "^[MADRC]"; then
            has_changes=true
        fi
        if echo "$status" | grep -q "^.[MADRC]"; then
            has_changes=true
        fi
        if echo "$status" | grep -q "^??"; then
            has_untracked=true
        fi
    fi
    
    # Check for remote
    local has_remote=false
    if git remote 2>/dev/null | grep -q .; then
        has_remote=true
    fi
    
    local ahead=0 behind=0
    
    if [[ "$has_remote" == true ]]; then
        # Fetch to check for updates (quiet)
        git fetch --all --quiet 2>/dev/null || true
        
        # Check ahead/behind
        local tracking
        tracking=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
        if [[ -n "$tracking" ]]; then
            ahead=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)
            behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)
        fi
    fi
    
    # Determine overall status
    if [[ "$has_remote" == false ]]; then
        REPO_STATUSES[$index]="no_remote"
        REPO_MESSAGES[$index]="No remote configured"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$has_changes" == true ]]; then
        REPO_STATUSES[$index]="dirty"
        REPO_MESSAGES[$index]="Has uncommitted changes"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
        REPO_STATUSES[$index]="diverged"
        REPO_MESSAGES[$index]="Diverged ($ahead ahead, $behind behind)"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$ahead" -gt 0 ]]; then
        REPO_STATUSES[$index]="ahead"
        REPO_MESSAGES[$index]="$ahead commits ahead (needs push)"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$behind" -gt 0 ]]; then
        REPO_STATUSES[$index]="behind"
        REPO_MESSAGES[$index]="$behind commits behind"
        REPO_CAN_PULL[$index]="true"
    else
        REPO_STATUSES[$index]="up_to_date"
        REPO_MESSAGES[$index]="Up to date"
        REPO_CAN_PULL[$index]="false"
    fi
    
    return 0
}

# Perform safe pull
do_safe_pull() {
    local repo_path=$1
    local index=$2
    
    cd "$repo_path" || return 1
    
    local before after
    before=$(git rev-parse HEAD 2>/dev/null)
    
    # Try fast-forward only pull
    if git pull --ff-only 2>/dev/null; then
        after=$(git rev-parse HEAD 2>/dev/null)
        
        if [[ "$before" == "$after" ]]; then
            REPO_MESSAGES[$index]="Already up to date"
        else
            local new_commits
            new_commits=$(git rev-list --count "${before}..${after}" 2>/dev/null || echo "?")
            REPO_MESSAGES[$index]="Pulled $new_commits new commit(s)"
        fi
        REPO_STATUSES[$index]="pulled"
        return 0
    else
        REPO_MESSAGES[$index]="Pull failed"
        return 1
    fi
}

# Get status icon for display
get_status_icon() {
    local status=$1
    case "$status" in
        "up_to_date"|"pulled") echo "✅" ;;
        "behind") echo "📥" ;;
        "ahead") echo "📤" ;;
        "diverged") echo "⚠️" ;;
        "dirty") echo "✏️" ;;
        "no_remote") echo "🔗" ;;
        *) echo "❓" ;;
    esac
}

# Scan all repos
run_repo_scan() {
    local dry_run=${1:-false}
    
    reset_results
    
    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue
        
        if [[ ! -d "$folder" ]]; then
            echo "⚠️  Folder not found: $folder"
            continue
        fi
        
        echo "📁 Scanning: $folder"
        
        # Get first-level subdirectories
        for subdir in "$folder"/*/; do
            [[ ! -d "$subdir" ]] && continue
            
            local repo_path="${subdir%/}"
            
            # Check if it's a git repo
            if [[ ! -d "$repo_path/.git" ]]; then
                continue
            fi
            
            local repo_name
            repo_name=$(basename "$repo_path")
            
            echo -n "   🔍 Checking: $repo_name..."
            
            # Get status
            local current_index=${#REPO_NAMES[@]}
            get_repo_status "$repo_path"
            
            # Show immediate status indicator
            local icon
            icon=$(get_status_icon "${REPO_STATUSES[$current_index]}")
            echo " $icon"
            
            # Try to pull if safe and not dry run
            if [[ "$dry_run" != "true" ]] && [[ "${REPO_CAN_PULL[$current_index]}" == "true" ]]; then
                echo -n "      ⬇️  Pulling..."
                if do_safe_pull "$repo_path" "$current_index"; then
                    echo " ${REPO_MESSAGES[$current_index]}"
                else
                    echo " Failed"
                fi
            fi
        done
    done < <(get_all_folders)
}
