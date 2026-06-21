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
declare -a REPO_CAN_PUSH
declare -a REPO_WAS_DIRTY
declare -a REPO_HAS_SUBMODULES
declare -a REPO_ORIGINAL_BRANCHES  # Store original branch for auto-pull/auto-push

# Reset results arrays
reset_results() {
    REPO_RESULTS=()
    REPO_NAMES=()
    REPO_PATHS=()
    REPO_STATUSES=()
    REPO_MESSAGES=()
    REPO_BRANCHES=()
    REPO_CAN_PULL=()
    REPO_CAN_PUSH=()
    REPO_WAS_DIRTY=()
    REPO_HAS_SUBMODULES=()
    REPO_ORIGINAL_BRANCHES=()
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
    REPO_CAN_PUSH[$index]="false"
    REPO_WAS_DIRTY[$index]="false"
    
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
    REPO_ORIGINAL_BRANCHES[$index]="$current_branch"  # Store for auto-pull restoration
    
    # Check for uncommitted changes
    local status has_changes=false has_untracked=false has_only_submodule_changes=false
    status=$(run_git_command status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        # Detect untracked files
        if echo "$status" | grep -q "^??"; then
            has_untracked=true
            has_changes=true
        fi
        # Detect non-submodule, non-untracked changes (staged/unstaged modifications)
        if echo "$status" | grep -v "^M " | grep -v "^??" | grep -q .; then
            has_changes=true
        fi
        # Only submodule changes if no other dirty state was detected
        if [[ "$has_changes" == false ]]; then
            if echo "$status" | grep -q "^M "; then
                has_only_submodule_changes=true
            fi
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
    
    # Determine overall status.
    # NOTE: branch analysis (canPush) must come before submodule classification so that
    # dirty repos with committed-ahead branches still get a push attempt.
    if [[ "$has_remote" == false ]]; then
        REPO_STATUSES[$index]="no_remote"
        REPO_MESSAGES[$index]="No remote configured"
    elif [[ "$has_changes" == true ]]; then
        # Dirty working tree — still allow push of committed-ahead branches.
        REPO_STATUSES[$index]="dirty"
        REPO_MESSAGES[$index]="Has uncommitted changes"
        REPO_CAN_PULL[$index]="false"
        REPO_WAS_DIRTY[$index]="true"
        if [[ "$any_ahead" -gt 0 && "$any_behind" -eq 0 && "$any_diverged" -eq 0 ]]; then
            REPO_CAN_PUSH[$index]="true"
        fi
    elif [[ "$has_only_submodule_changes" == true ]]; then
        # Only submodule pointer changes — check whether those submodules need updating.
        check_submodules "$repo_path" "$index"
        if [[ "${REPO_STATUSES[$index]}" == "submodule_updates" ]]; then
            REPO_CAN_PULL[$index]="true"
        else
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
        if [[ "$any_behind" -eq 0 ]]; then
            REPO_CAN_PUSH[$index]="true"
        fi
    else
        # Clean and up to date — run submodule check as final pass.
        check_submodules "$repo_path" "$index"
        if [[ "${REPO_STATUSES[$index]}" == "submodule_updates" ]]; then
            REPO_CAN_PULL[$index]="true"
        else
            REPO_STATUSES[$index]="up_to_date"
            REPO_MESSAGES[$index]="All branches up to date"
            REPO_CAN_PULL[$index]="false"
        fi
    fi
    
    return 0
}

# Perform safe push on all branches that are strictly ahead of their upstream.
#
# Args:
#   $1 - repo_path: Path to the git repository.
#   $2 - index: Array index for this repository in global REPO_* arrays.
#
# Sets:
#   REPO_STATUSES[$index] to "auto_pushed" on full success.
#   REPO_MESSAGES[$index] with push result details.
#
# Returns:
#   0 on success (all eligible branches pushed), 1 on partial or full failure.
do_safe_push() {
    local repo_path=$1
    local index=$2

    cd "$repo_path" || return 1

    local original_branch="${REPO_ORIGINAL_BRANCHES[$index]}"
    local pushed_count=0
    local failed_count=0
    local push_details=""

    while IFS='|' read -r branch upstream; do
        [[ -z "$branch" || -z "$upstream" ]] && continue

        local ahead behind
        ahead=$(run_git_command rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)
        behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)

        # Skip branches that are not ahead
        [[ "$ahead" -eq 0 ]] && continue

        # Skip diverged branches — require manual merge
        if [[ "$behind" -gt 0 ]]; then
            failed_count=$((failed_count + 1))
            continue
        fi

        # Switch to branch if needed
        if [[ "$branch" != "$original_branch" ]]; then
            if ! run_git_command checkout "$branch" --quiet; then
                failed_count=$((failed_count + 1))
                continue
            fi
        fi

        # Push (non-force, standard fast-forward)
        if run_git_command push &>/dev/null; then
            pushed_count=$((pushed_count + 1))
            push_details="${push_details}${branch} (${ahead} commit(s)), "
        else
            failed_count=$((failed_count + 1))
        fi

        # Return to original branch if we switched
        if [[ "$branch" != "$original_branch" ]]; then
            run_git_command checkout "$original_branch" --quiet
        fi
    done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)

    # Restore original branch
    local current_branch
    current_branch=$(run_git_command rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" != "$original_branch" ]]; then
        run_git_command checkout "$original_branch" --quiet
    fi

    # Trim trailing comma+space from details
    push_details="${push_details%, }"

    if [[ "$pushed_count" -gt 0 && "$failed_count" -eq 0 ]]; then
        REPO_STATUSES[$index]="auto_pushed"
        REPO_MESSAGES[$index]="Pushed: $push_details"
        return 0
    elif [[ "$pushed_count" -gt 0 ]]; then
        REPO_MESSAGES[$index]="Partial push: $pushed_count pushed, $failed_count failed"
        return 1
    else
        REPO_MESSAGES[$index]="Push failed - manual push required"
        return 1
    fi
}

# Perform safe pull on all branches
do_safe_pull() {
    local repo_path=$1
    local index=$2
    
    cd "$repo_path" || return 1
    
    local original_branch="${REPO_ORIGINAL_BRANCHES[$index]}"
    local repo_status="${REPO_STATUSES[$index]}"
    
    local pulled_count=0
    local total_behind=0
    local fail_count=0
    
    # Handle 'behind' repos with auto-pull logic
    if [[ "$repo_status" == "behind" ]]; then
        # Get branches that are behind
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
                
                # Check if clean (should be, but double-check)
                if [[ -n "$(run_git_command status --porcelain 2>/dev/null)" ]]; then
                    # Not clean, skip this branch
                    if [[ "$branch" != "$original_branch" ]]; then
                        run_git_command checkout "$original_branch" --quiet
                    fi
                    fail_count=$((fail_count + 1))
                    continue
                fi
                
                # Try pull
                if run_git_command pull --ff-only &>/dev/null; then
                    pulled_count=$((pulled_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
                
                # Return to original branch if we switched
                if [[ "$branch" != "$original_branch" ]]; then
                    run_git_command checkout "$original_branch" --quiet
                fi
            fi
        done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
        
        # Update status based on results
        if [[ "$fail_count" -eq 0 ]]; then
            REPO_STATUSES[$index]="pulled"
            REPO_MESSAGES[$index]="Auto-pulled $pulled_count branch(es)"
        else
            REPO_MESSAGES[$index]="Partial: $pulled_count pulled, $fail_count failed"
        fi
        
        return $((fail_count == 0 ? 0 : 1))
    fi
    
    # Original logic for other cases (submodule_updates, etc.)
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
        "auto_pushed") echo "⬆️✅" ;;
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
    local test_limit=${2:-0}
    
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

            # Auto-push branches that are strictly ahead (no diverge, remote in sync)
            if [[ "$dry_run" != "true" ]] && [[ "${REPO_CAN_PUSH[$current_index]}" == "true" ]]; then
                echo -n "      [^] Pushing..."
                if do_safe_push "$repo_path" "$current_index"; then
                    echo " ${REPO_MESSAGES[$current_index]}"
                else
                    echo " ${REPO_MESSAGES[$current_index]}"
                fi
            fi
            
            # Check test limit
            if [[ "$test_limit" -gt 0 && "${#REPO_NAMES[@]}" -ge "$test_limit" ]]; then
                echo ""
                echo "[i] Test limit reached: checked $test_limit repositories"
                break
            fi
        done
        
        # Check test limit after each folder
        if [[ "$test_limit" -gt 0 && "${#REPO_NAMES[@]}" -ge "$test_limit" ]]; then
            break
        fi
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
    
    # Classify submodules by prefix:
    #   '-' = not initialized -> needs 'submodule update --remote' then stage+commit
    #   '+' = working tree at different commit than parent index -> only stage+commit pointer
    #         (do NOT run --remote: would loop forever if submodule is already at remote HEAD)
    local submodules_to_fetch=()  # '-' prefix
    local submodules_to_stage=()  # '+' prefix

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local prefix="${line:0:1}"
        # Path is second whitespace-delimited field (after hash)
        local sub_path
        sub_path=$(echo "${line#[-+ ]}" | awk '{print $2}')
        [[ -z "$sub_path" ]] && continue
        if [[ "$prefix" == "-" ]]; then
            submodules_to_fetch+=("$sub_path")
        elif [[ "$prefix" == "+" ]]; then
            submodules_to_stage+=("$sub_path")
        fi
    done < <(run_git_command -C "$repo_path" submodule status 2>/dev/null | grep '^[+-]')

    local all_submodules=("${submodules_to_fetch[@]}" "${submodules_to_stage[@]}")

    if [[ "${#all_submodules[@]}" -eq 0 ]]; then
        echo "   ℹ️  No submodule updates needed"
        return 0
    fi
    
    local updated_count=0
    local failed_count=0

    # Run --remote only for uninitialized ('-') submodules
    for submodule in "${submodules_to_fetch[@]}"; do
        echo "   🔄 Updating $submodule..."
        if run_git_command -C "$repo_path" submodule update --remote "$submodule" &>/dev/null; then
            echo "   ✅ Updated $submodule"
            ((updated_count++))
        else
            echo "   ❌ Failed to update $submodule"
            ((failed_count++))
        fi
    done

    # For '+' submodules, only stage+commit the pointer (no --remote)
    for submodule in "${submodules_to_stage[@]}"; do
        echo "   📌 Staging pointer update for $submodule..."
        ((updated_count++))
    done
    
    # Stage each submodule path individually and commit pointer changes
    if [[ "$updated_count" -gt 0 ]]; then
        echo "   📝 Committing submodule updates..."
        for submodule in "${all_submodules[@]}"; do
            run_git_command -C "$repo_path" add "$submodule" &>/dev/null
        done
        # Check whether staging produced any changes
        if run_git_command -C "$repo_path" diff --cached --quiet &>/dev/null; then
            # Nothing staged — parent index already matches working tree commits
            echo "   ℹ️  Submodules already at expected commit, no commit needed"
            return 0
        else
            if run_git_command -C "$repo_path" commit -m "Auto-update submodules ($updated_count updated)" &>/dev/null; then
                echo "   ✅ Committed submodule updates"
            else
                echo "   ❌ Failed to commit submodule updates"
                return 1
            fi
        fi
        echo ""
        echo "⚠️  IMPORTANT: Submodules were automatically updated!"
        echo "   🧪 Please test $repo_name to ensure it still works as expected"
        echo "   📋 Review the submodule changes: git log --oneline -5"
    fi
    
    return 0
}
