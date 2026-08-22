#!/usr/bin/env bash
# =============================================================================
# Module: test-repository-discovery.sh
#
# Description:
#     Verifies repository and first-level container discovery without running
#     networked Git operations.
# =============================================================================

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${TEST_ROOT}/modules/git-operations.sh"

TEST_DIRECTORY="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIRECTORY"' EXIT

DIRECT_REPOSITORY="${TEST_DIRECTORY}/coding-guidelines"
NESTED_CONTAINER="${TEST_DIRECTORY}/nested"
NESTED_REPOSITORY="${NESTED_CONTAINER}/nested-repository"
mkdir -p \
    "${DIRECT_REPOSITORY}/.git" \
    "${NESTED_REPOSITORY}/.git"

# Supply one repository watch entry to verify direct detection first.
get_all_folders() {
    printf '%s\n' "$DIRECT_REPOSITORY"
}

# Record scanner results without invoking Git or changing the disposable repos.
get_repo_status() {
    local repo_path=$1
    local index=${#REPO_NAMES[@]}

    REPO_PATHS[$index]="$repo_path"
    REPO_NAMES[$index]=$(basename "$repo_path")
    REPO_STATUSES[$index]="up_to_date"
    REPO_MESSAGES[$index]="Test repository"
    REPO_BRANCHES[$index]="main"
    REPO_CAN_PULL[$index]="false"
    REPO_CAN_PUSH[$index]="false"
    REPO_WAS_DIRTY[$index]="false"
}

run_repo_scan true

if [[ "${#REPO_PATHS[@]}" -ne 1 || "${REPO_PATHS[0]}" != "$DIRECT_REPOSITORY" ]]; then
    printf '%s\n' "Direct repository watch entry was not detected." >&2
    exit 1
fi

# Supply overlapping watch entries to verify that parent-folder discoveries
# remain deduplicated.
get_all_folders() {
    printf '%s\n' \
        "$TEST_DIRECTORY" \
        "$DIRECT_REPOSITORY" \
        "$NESTED_CONTAINER"
}

run_repo_scan true

if [[ "${#REPO_PATHS[@]}" -ne 2 ]]; then
    printf 'Expected 2 unique repositories, found %s.\n' "${#REPO_PATHS[@]}" >&2
    exit 1
fi

if [[ " ${REPO_PATHS[*]} " != *" $NESTED_REPOSITORY "* ]]; then
    printf '%s\n' "First-level repository inside a watched container was not detected." >&2
    exit 1
fi

printf '%s\n' "Bash repository discovery passed."
