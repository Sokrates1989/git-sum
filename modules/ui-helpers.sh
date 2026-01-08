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
    local up_to_date=0 pulled=0 behind=0 ahead=0 diverged=0 dirty=0 no_remote=0 errors=0
    
    for i in "${!REPO_STATUSES[@]}"; do
        case "${REPO_STATUSES[$i]}" in
            "up_to_date") ((up_to_date++)) ;;
            "pulled") ((pulled++)) ;;
            "behind") ((behind++)) ;;
            "ahead") ((ahead++)) ;;
            "diverged") ((diverged++)) ;;
            "dirty") ((dirty++)) ;;
            "no_remote") ((no_remote++)) ;;
            "error"|"not_git") ((errors++)) ;;
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
    [[ "$pulled" -gt 0 ]] && echo "   [OK] Pulled:      $pulled"
    [[ "$up_to_date" -gt 0 ]] && echo "   [OK] Up to date:  $up_to_date"
    [[ "$behind" -gt 0 ]] && echo "   [v] Behind:      $behind"
    [[ "$ahead" -gt 0 ]] && echo "   [^] Ahead:       $ahead"
    [[ "$diverged" -gt 0 ]] && echo "   [!] Diverged:    $diverged"
    [[ "$dirty" -gt 0 ]] && echo "   [~] Dirty:       $dirty"
    [[ "$no_remote" -gt 0 ]] && echo "   [-] No remote:   $no_remote"
    [[ "$errors" -gt 0 ]] && echo "   [X] Errors:      $errors"
    
    # Show repos that need attention
    local needs_attention=$((behind + ahead + diverged + dirty + no_remote + errors))
    
    if [[ "$needs_attention" -gt 0 ]]; then
        echo ""
        echo "---------------------------------------------------------------"
        echo "[!] Repositories Needing Attention"
        echo "---------------------------------------------------------------"
        echo ""
        
        for i in "${!REPO_STATUSES[@]}"; do
            local status="${REPO_STATUSES[$i]}"
            case "$status" in
                "behind"|"ahead"|"diverged"|"dirty"|"no_remote"|"error"|"not_git")
                    show_repo_attention "$i" "$dry_run"
                    ;;
            esac
        done
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
    
    local status="${REPO_STATUSES[$index]}"
    local icon
    
    case "$status" in
        "behind") icon="[v]" ;;
        "ahead") icon="[^]" ;;
        "diverged") icon="[!]" ;;
        "dirty") icon="[~]" ;;
        "no_remote") icon="[-]" ;;
        "error") icon="[X]" ;;
        "not_git") icon="[?]" ;;
        *) icon="*" ;;
    esac
    
    echo "   $icon ${REPO_NAMES[$index]}"
    echo "      Path:   ${REPO_PATHS[$index]}"
    
    if [[ "$status" == "dirty" ]]; then
        echo "      Status: ${REPO_MESSAGES[$index]} (on branch: ${REPO_BRANCHES[$index]})"
    elif [[ "$status" == "no_remote" ]]; then
        echo "      Status: ${REPO_MESSAGES[$index]}"
    elif [[ "$status" == "error" ]]; then
        echo "      Error:  ${REPO_MESSAGES[$index]}"
    else
        # Show status for all branches that need attention
        cd "${REPO_PATHS[$index]}" || return
        while IFS='|' read -r branch upstream; do
            [[ -z "$branch" || -z "$upstream" ]] && continue
            
            local ahead behind
            ahead=$(run_git_command rev-list --count "$upstream..$branch" 2>/dev/null || echo 0)
            behind=$(run_git_command rev-list --count "$branch..$upstream" 2>/dev/null || echo 0)
            
            if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;31mDiverged ($ahead ahead, $behind behind)\033[0m"
            elif [[ "$ahead" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;34m$ahead commits ahead\033[0m"
            elif [[ "$behind" -gt 0 ]]; then
                echo -e "      Branch $branch: \033[0;33m$behind commits behind\033[0m"
            fi
        done < <(run_git_command branch --format="%(refname:short)|%(upstream:short)" 2>/dev/null)
    fi
    
    # Suggest fix
    local suggestion
    suggestion=$(get_fix_suggestion "$index")
    if [[ -n "$suggestion" ]]; then
        echo "      [>] $suggestion"
    fi
    
    echo ""
}

# Get fix suggestion for a repo issue
get_fix_suggestion() {
    local index=$1
    local status="${REPO_STATUSES[$index]}"
    local path="${REPO_PATHS[$index]}"
    
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
            echo "Commit or stash changes: cd \"$path\" && git stash"
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
