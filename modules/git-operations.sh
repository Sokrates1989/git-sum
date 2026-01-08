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
declare -a REPO_HAS_SUBMODULES

# Reset results arrays
reset_results() {
    REPO_RESULTS=()
    REPO_NAMES=()
    REPO_PATHS=()
    REPO_STATUSES=()
    REPO_MESSAGES=()
    REPO_BRANCHES=()
    REPO_CAN_PULL=()
    REPO_HAS_SUBMODULES=()
}

# Run git command non-interactively with a hard timeout
run_git_command() {
    local timeout_secs=20
    
    # Set environment variables to prevent interactive prompts
    # Use 'timeout' command if available, otherwise run normally with env vars
    if command -v timeout &>/dev/null; then
        GIT_TERMINAL_PROMPT=0 \
        GCM_INTERACTIVE=never \
        GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
        timeout "$timeout_secs" git "$@" 2>/dev/null
    else
        # Fallback for systems without 'timeout' (like some macOS versions)
        GIT_TERMINAL_PROMPT=0 \
        GCM_INTERACTIVE=never \
        GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
        git "$@" 2>/dev/null
    fi
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
    if ! run_git_command rev-parse --git-dir &>/dev/null; then
        REPO_STATUSES[$index]="not_git"
        REPO_MESSAGES[$index]="Not a git repository"
        return 0
    fi
    
    # Get current branch
    local current_branch
    current_branch=$(run_git_command rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$current_branch" ]]; then
        current_branch="(detached)"
    fi
    REPO_BRANCHES[$index]="$current_branch"
    
    # Check for uncommitted changes
    local status has_changes=false has_untracked=false has_only_submodule_changes=false
    status=$(run_git_command status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        # Check if all changes are submodule changes
        if echo "$status" | grep -v "^M " | grep -v "^??" | grep -q .; then
            has_changes=true
        else
            # Only submodule changes detected
            has_only_submodule_changes=true
        fi
        if echo "$status" | grep -q "^??"; then
            has_untracked=true
        fi
    fi
    
    # Check for remote
    local has_remote=false
    if run_git_command remote 2>/dev/null | grep -q .; then
        has_remote=true
    fi
    
    local any_ahead=0 any_behind=0 any_diverged=0
    
    if [[ "$has_remote" == true ]]; then
        # Fetch to check for updates (quiet, non-interactive)
        run_git_command fetch --all --quiet &>/dev/null || true
        
        # Get all local branches and their status relative to upstream
        while IFS='|' read -r branch upstream; do
            [[ -z "$branch" || -z "$upstream" ]] && continue
            
            local ahead behind
            ahead=$(run_git_command rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)
            behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)
            
            if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
                any_diverged=$((any_diverged + 1))
            elif [[ "$ahead" -gt 0 ]]; then
                any_ahead=$((any_ahead + 1))
            elif [[ "$behind" -gt 0 ]]; then
                any_behind=$((any_behind + 1))
            fi
        done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
    fi
    
    # Determine overall status
    if [[ "$has_remote" == false ]]; then
        REPO_STATUSES[$index]="no_remote"
        REPO_MESSAGES[$index]="No remote configured"
    fi
    
    # Check for submodule updates (even if only submodule changes exist)
    if [[ "$any_diverged" -eq 0 ]]; then
        check_submodules "$repo_path" "$index"
        # If submodules have updates, that becomes the primary status
        if [[ "${REPO_STATUSES[$index]}" == "submodule_updates" ]]; then
            REPO_CAN_PULL[$index]="true"  # Allow pulling to update submodules
            return 0
        fi
    fi
    
    # Set final status based on branch analysis
    if [[ "$has_changes" == true ]]; then
        REPO_STATUSES[$index]="dirty"
        REPO_MESSAGES[$index]="Has uncommitted changes"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$has_only_submodule_changes" == true ]]; then
        # Repository is only dirty due to submodule changes - treat as submodule updates
        check_submodules "$repo_path" "$index"
        if [[ "${REPO_STATUSES[$index]}" == "submodule_updates" ]]; then
            REPO_CAN_PULL[$index]="true"  # Allow pulling to update submodules
            return 0
        else
            # Submodule changes but no updates available
            REPO_STATUSES[$index]="dirty"
            REPO_MESSAGES[$index]="Has submodule changes"
            REPO_CAN_PULL[$index]="false"
        fi
    elif [[ "$any_diverged" -gt 0 ]]; then
        REPO_STATUSES[$index]="diverged"
        REPO_MESSAGES[$index]="Some branches diverged"
        REPO_CAN_PULL[$index]="false"
    elif [[ "$any_behind" -gt 0 ]]; then
        REPO_STATUSES[$index]="behind"
        REPO_MESSAGES[$index]="$any_behind branch(es) behind"
        REPO_CAN_PULL[$index]="true"
    elif [[ "$any_ahead" -gt 0 ]]; then
        REPO_STATUSES[$index]="ahead"
        REPO_MESSAGES[$index]="$any_ahead branch(es) ahead"
        REPO_CAN_PULL[$index]="false"
    else
        REPO_STATUSES[$index]="up_to_date"
        REPO_MESSAGES[$index]="All branches up to date"
        REPO_CAN_PULL[$index]="false"
    fi
    
    return 0
}

# Perform safe pull on all branches
do_safe_pull() {
    local repo_path=$1
    local index=$2
    
    cd "$repo_path" || return 1
    
    local original_branch
    original_branch=$(run_git_command rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    local pulled_count=0
    local total_behind=0
    local fail_count=0
    
    # Get branches that track upstream
    while IFS='|' read -r branch upstream; do
        [[ -z "$branch" || -z "$upstream" ]] && continue
        
        local behind
        behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)
        
        if [[ "$behind" -gt 0 ]]; then
            total_behind=$((total_behind + 1))
            
            # Switch to branch if needed
            if [[ "$branch" != "$original_branch" ]]; then
                if ! run_git_command checkout "$branch" --quiet; then
                    fail_count=$((fail_count + 1))
                    continue
                fi
            fi
            
            # Check if clean
            if [[ -n "$(run_git_command status --porcelain 2>/dev/null)" ]]; then
                fail_count=$((fail_count + 1))
                [[ "$branch" != "$original_branch" ]] && run_git_command checkout "$original_branch" --quiet
                continue
            fi
            
            # Try pull
            if run_git_command pull --ff-only &>/dev/null; then
                pulled_count=$((pulled_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        fi
    done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
    
    # Return to original branch
    local current_branch
    current_branch=$(run_git_command rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" != "$original_branch" ]]; then
        run_git_command checkout "$original_branch" --quiet
    fi
    
    # Check and update submodules if this was a submodule update repo
    if [[ "${REPO_STATUSES[$index]}" == "submodule_updates" ]]; then
        local repo_name="${REPO_NAMES[$index]}"
        if update_submodules "$repo_path" "$repo_name"; then
            REPO_STATUSES[$index]="pulled"
            REPO_MESSAGES[$index]="Updated submodules"
            return 0
        else
            REPO_STATUSES[$index]="submodule_updates"
            REPO_MESSAGES[$index]="Failed to update submodules"
            return 1
        fi
    fi
    
    if [[ "$fail_count" -eq 0 ]]; then
        REPO_STATUSES[$index]="pulled"
        REPO_MESSAGES[$index]="Updated $pulled_count branch(es)"
        return 0
    else
        REPO_STATUSES[$index]="behind"
        REPO_MESSAGES[$index]="Updated $pulled_count, $fail_count failed"
        return 1
    fi
}

# Get status icon for display
get_status_icon() {
    local status=$1
    case "$status" in
        "up_to_date"|"pulled") echo "✅" ;;
        "behind") echo "⬇️" ;;
        "ahead") echo "⬆️" ;;
        "diverged") echo "⚠️" ;;
        "dirty") echo "📝" ;;
        "no_remote") echo "🔗" ;;
        "submodule_updates") echo "📦" ;;
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
            echo "[!] Folder not found: $folder"
            continue
        fi
        
        echo "[>] Scanning: $folder"
        
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
            
            echo -n "   [?] Checking: $repo_name..."
            
            # Get status
            local current_index=${#REPO_NAMES[@]}
            get_repo_status "$repo_path"
            
            # Show immediate status indicator
            local icon
            icon=$(get_status_icon "${REPO_STATUSES[$current_index]}")
            echo " $icon"
            
            # Try to pull if safe and not dry run
            if [[ "$dry_run" != "true" ]] && [[ "${REPO_CAN_PULL[$current_index]}" == "true" ]]; then
                echo -n "      [v] Pulling..."
                if do_safe_pull "$repo_path" "$current_index"; then
                    echo " ${REPO_MESSAGES[$current_index]}"
                else
                    echo " Failed"
                fi
            fi
        done
    done < <(get_all_folders)
}

# Check if repository has submodules with updates available
check_submodules() {
    local repo_path=$1
    local index=$2
    
    # Check if repository has submodules
    if ! run_git_command -C "$repo_path" submodule status &>/dev/null; then
        REPO_HAS_SUBMODULES[$index]=false
        return 0
    fi
    
    # Get submodule status
    local submodule_status
    submodule_status=$(run_git_command -C "$repo_path" submodule status 2>/dev/null)
    
    if [[ -z "$submodule_status" ]]; then
        REPO_HAS_SUBMODULES[$index]=false
        return 0
    fi
    
    REPO_HAS_SUBMODULES[$index]=true
    
    # Check if any submodules have new commits
    local has_updates=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[+-] ]]; then
            has_updates=true
            break
        fi
    done <<< "$submodule_status"
    
    if [[ "$has_updates" == true ]]; then
        REPO_STATUSES[$index]="submodule_updates"
        REPO_MESSAGES[$index]="Submodules have updates available"
        return 1
    fi
    
    return 0
}

# Update submodules safely
update_submodules() {
    local repo_path=$1
    local repo_name=$2
    
    echo ""
    echo "📦 Updating submodules in $repo_name..."
    
    # Get list of submodules that need updates
    local submodules_to_update
    submodules_to_update=$(run_git_command -C "$repo_path" submodule status 2>/dev/null | grep '^[+-]' | awk '{print $2}')
    
    if [[ -z "$submodules_to_update" ]]; then
        echo "   ℹ️  No submodule updates needed"
        return 0
    fi
    
    local updated_count=0
    local failed_count=0
    
    while IFS= read -r submodule; do
        if [[ -n "$submodule" ]]; then
            echo "   🔄 Updating $submodule..."
            if run_git_command -C "$repo_path" submodule update --remote "$submodule" &>/dev/null; then
                echo "   ✅ Updated $submodule"
                ((updated_count++))
            else
                echo "   ❌ Failed to update $submodule"
                ((failed_count++))
            fi
        fi
    done <<< "$submodules_to_update"
    
    # Commit submodule updates if any were successful
    if [[ "$updated_count" -gt 0 ]]; then
        echo "   📝 Committing submodule updates..."
        if run_git_command -C "$repo_path" add . &>/dev/null && \
           run_git_command -C "$repo_path" commit -m "Auto-update submodules ($updated_count updated)" &>/dev/null; then
            echo "   ✅ Committed submodule updates"
            echo ""
            echo "⚠️  IMPORTANT: Submodules were automatically updated!"
            echo "   🧪 Please test $repo_name to ensure it still works as expected"
            echo "   📋 Review the submodule changes: git log --oneline -5"
            return 0
        else
            echo "   ❌ Failed to commit submodule updates"
            return 1
        fi
    fi
    
    return 0
}
