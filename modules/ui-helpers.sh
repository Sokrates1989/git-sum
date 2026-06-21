#!/bin/bash
#
# UI helper functions for git-sum (Bash)
#
# Description:
#   Provides functions for displaying formatted output, summaries, and interactive elements.

# Display summary of repo scan results
show_summary() {
    local dry_run=${1:-false}
    local total=${#REPO_NAMES[@]}
    
    if [[ "$total" -eq 0 ]]; then
        echo ""
        echo "[!] No repositories found in watched folders."
        echo "   Run 'git-sum -a' to add folders containing git repos."
        return
    fi
    
    # Count by status
    local up_to_date=0 pulled=0 auto_pushed=0 behind=0 ahead=0 diverged=0 dirty=0 no_remote=0 submodule_updates=0 errors=0
    
    for i in "${!REPO_STATUSES[@]}"; do
        case "${REPO_STATUSES[$i]}" in
            "up_to_date") ((up_to_date++)) ;;
            "pulled") ((pulled++)) ;;
            "auto_pushed") ((auto_pushed++)) ;;
            "behind") ((behind++)) ;;
            "ahead") ((ahead++)) ;;
            "diverged") ((diverged++)) ;;
            "dirty") ((dirty++)) ;;
            "no_remote") ((no_remote++)) ;;
            "submodule_updates") ((submodule_updates++)) ;;
            "error") ((errors++)) ;;
        esac
    done
    
    echo ""
    echo "==============================================================="
    echo "[*] Summary"
    echo "==============================================================="
    echo ""
    
    # Quick stats line
    echo "   Total repositories scanned: $total"
    echo ""
    
    # Status breakdown
    [[ "$pulled" -gt 0 ]] && echo "   ✅ Pulled:      $pulled"
    [[ "$auto_pushed" -gt 0 ]] && echo "   ⬆️ Pushed:      $auto_pushed"
    [[ "$up_to_date" -gt 0 ]] && echo "   ✅ Up to date:  $up_to_date"
    [[ "$behind" -gt 0 ]] && echo "   ⬇️ Behind:      $behind"
    [[ "$ahead" -gt 0 ]] && echo "   ⬆️ Ahead:       $ahead"
    [[ "$diverged" -gt 0 ]] && echo "   ⚠️ Diverged:    $diverged"
    [[ "$dirty" -gt 0 ]] && echo "   📝 Dirty:       $dirty"
    [[ "$no_remote" -gt 0 ]] && echo "   🔗 No remote:   $no_remote"
    [[ "$submodule_updates" -gt 0 ]] && echo "   📦 Submodules:   $submodule_updates"
    [[ "$errors" -gt 0 ]] && echo "   ❌ Errors:      $errors"
    
    # Show successfully updated/pushed repos (so user sees what changed)
    if [[ "$pulled" -gt 0 || "$auto_pushed" -gt 0 ]]; then
        echo ""
        echo "---------------------------------------------------------------"
        echo "[OK] Successfully Updated Repositories"
        echo "---------------------------------------------------------------"
        echo ""
        
        for i in "${!REPO_STATUSES[@]}"; do
            if [[ "${REPO_STATUSES[$i]}" == "pulled" ]]; then
                echo "   [OK] ${REPO_NAMES[$i]}"
                echo "      Path:    ${REPO_PATHS[$i]}"
                echo "      Updated: ${REPO_MESSAGES[$i]}"
                echo ""
            fi
        done

        for i in "${!REPO_STATUSES[@]}"; do
            if [[ "${REPO_STATUSES[$i]}" == "auto_pushed" ]]; then
                echo "   [^] ${REPO_NAMES[$i]}"
                echo "      Path:    ${REPO_PATHS[$i]}"
                echo "      Pushed:  ${REPO_MESSAGES[$i]}"
                if [[ "${REPO_WAS_DIRTY[$i]:-false}" == "true" ]]; then
                    echo "      [~] Note: repo still has local uncommitted changes"
                fi
                echo ""
            fi
        done
    fi
    
    # Show repos that need attention
    local needs_attention=$((behind + ahead + diverged + dirty + no_remote + submodule_updates + errors))  # ahead = failed-push repos
    
    if [[ "$needs_attention" -gt 0 ]]; then
        echo ""
        echo "---------------------------------------------------------------"
        echo "[!] Repositories Needing Attention"
        echo "---------------------------------------------------------------"
        echo ""
        
        for i in "${!REPO_STATUSES[@]}"; do
            local status="${REPO_STATUSES[$i]}"
            case "$status" in
                "behind"|"ahead"|"diverged"|"dirty"|"no_remote"|"submodule_updates"|"error"|"not_git")  # ahead = failed push
                    show_repo_attention "$i" "$dry_run"
                    ;;
            esac
        done
        
        if [[ "$needs_attention" -gt 1 ]]; then
            echo ""
            echo "==============================================================="
            echo "[*] Summary (Repeated)"
            echo "==============================================================="
            echo ""
            
            echo "   Total repositories scanned: $total"
            echo ""
            
            echo "   ✅ Pulled:      $pulled"
            [[ "$auto_pushed" -gt 0 ]] && echo "   ⬆️ Pushed:      $auto_pushed"
            echo "   ✅ Up to date:  $up_to_date"
            echo "   ⬇️ Behind:      $behind"
            echo "   ⬆️ Ahead:       $ahead"
            echo "   ⚠️ Diverged:    $diverged"
            echo "   📝 Dirty:       $dirty"
            echo "   🔗 No remote:   $no_remote"
            echo "   📦 Submodules:   $submodule_updates"
            echo "   ❌ Errors:      $errors"
        fi
    fi
    
    echo ""
    echo "==============================================================="
    
    if [[ "$dry_run" == "true" ]]; then
        echo "   (Dry run - no changes were made)"
        echo "   Run 'git-sum' without -s to pull updates"
    fi
    
    echo ""
}

# Show details for a repo that needs attention
show_repo_attention() {
    local index=$1
    local dry_run=$2
    local has_branch_issues=false
    
    local status="${REPO_STATUSES[$index]}"
    local icon
    
    case "$status" in
        "behind") icon="⬇️" ;;
        "ahead") icon="⬆️" ;;
        "diverged") icon="⚠️" ;;
        "dirty") icon="📝" ;;
        "no_remote") icon="🔗" ;;
        "submodule_updates") icon="📦" ;;
        "error") icon="❌" ;;
        "not_git") icon="❓" ;;
        *) icon="❓" ;;
    esac
    
    echo "   $icon ${REPO_NAMES[$index]}"
    echo "      Path:   ${REPO_PATHS[$index]}"
    
    if [[ "$status" == "dirty" ]]; then
        echo "      Status: ${REPO_MESSAGES[$index]} (on branch: ${REPO_BRANCHES[$index]})"
    elif [[ "$status" == "no_remote" ]]; then
        echo "      Status: ${REPO_MESSAGES[$index]}"
    elif [[ "$status" == "error" ]]; then
        echo "      Error:  ${REPO_MESSAGES[$index]}"
    elif [[ "$status" == "submodule_updates" ]]; then
        echo "      Status: ${REPO_MESSAGES[$index]}"
        echo "      🔄 Will auto-update submodules when pulling"
    else
        # Show status for all branches that need attention
        cd "${REPO_PATHS[$index]}" || return
        local current_branch="${REPO_BRANCHES[$index]}"
        local has_branch_issues=false
        
        while IFS='|' read -r branch upstream; do
            [[ -z "$branch" || -z "$upstream" ]] && continue
            
            local ahead behind
            ahead=$(run_git_command rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)
            behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)
            
            if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;31mDiverged ($ahead ahead, $behind behind)\033[0m"
                has_branch_issues=true
            elif [[ "$ahead" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;34m$ahead commits ahead\033[0m"
                has_branch_issues=true
            elif [[ "$behind" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;33m$behind commits behind\033[0m"
                has_branch_issues=true
            fi
        done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
        
        # Create branch-specific commands
        if [[ "$has_branch_issues" == true ]]; then
            echo "      [>] Run individual branches:"
            cd "${REPO_PATHS[$index]}" || return
            while IFS='|' read -r branch upstream; do
                [[ -z "$branch" || -z "$upstream" ]] && continue
                
                local ahead behind
                ahead=$(run_git_command rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)
                behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)
                
                if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
                    echo "         cd \"${REPO_PATHS[$index]}\""
                    echo "         git checkout $branch"
                    echo "         git status"
                elif [[ "$ahead" -gt 0 ]]; then
                    echo "         cd \"${REPO_PATHS[$index]}\""
                    echo "         git checkout $branch"
                    echo "         git push"
                elif [[ "$behind" -gt 0 ]]; then
                    echo "         cd \"${REPO_PATHS[$index]}\""
                    echo "         git checkout $branch"
                    echo "         git pull"
                fi
            done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
        fi
    fi
    
    # Suggest fix (only if no branch-specific commands were shown)
    if [[ "$has_branch_issues" != true ]]; then
        local suggestion
        suggestion=$(get_fix_suggestion "$index" "$status")
        if [[ -n "$suggestion" ]]; then
            echo "      [>] Check repository status:"
            # Split the suggestion into multiple lines for easier copying
            if [[ "$suggestion" =~ cd\ \"([^\"]+)\" ]]; then
                local path="${BASH_REMATCH[1]}"
                local command=$(echo "$suggestion" | sed 's/.*cd "[^"]*" && //')
                echo "         cd \"$path\"; $command"
            fi
        fi
    fi
    
    echo ""
}

# Get fix suggestion for a repo issue
get_fix_suggestion() {
    local index=$1
    local status="${REPO_STATUSES[$index]}"
    local path="${REPO_PATHS[$index]}"
    local current_branch="${REPO_BRANCHES[$index]}"
    
    case "$status" in
        "behind")
            echo "Run: cd \"$path\" && git pull"
            ;;
        "ahead")
            echo "Run: cd \"$path\" && git push"
            ;;
        "diverged")
            echo "Manual merge needed. Run: cd \"$path\" && git status"
            ;;
        "dirty")
            echo "Check repository status: cd \"$path\" && git status"
            ;;
        "submodule_updates")
            echo "Auto-update submodules: cd \"$path\" && git-sum"
            ;;
        "no_remote")
            echo "Add remote: cd \"$path\" && git remote add origin <url>"
            ;;
        "error")
            echo "Check repository: cd \"$path\" && git status"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Print colored text (if terminal supports it)
print_color() {
    local color=$1
    local text=$2
    
    local code
    case "$color" in
        "red") code="\033[0;31m" ;;
        "green") code="\033[0;32m" ;;
        "yellow") code="\033[0;33m" ;;
        "blue") code="\033[0;34m" ;;
        "magenta") code="\033[0;35m" ;;
        "cyan") code="\033[0;36m" ;;
        "gray") code="\033[0;90m" ;;
        *) code="" ;;
    esac
    
    local reset="\033[0m"
    
    if [[ -t 1 ]]; then
        echo -e "${code}${text}${reset}"
    else
        echo "$text"
    fi
}
