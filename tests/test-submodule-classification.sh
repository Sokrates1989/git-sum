#!/usr/bin/env bash
# =============================================================================
# Module: test-submodule-classification.sh
#
# Description:
#     Verifies that no-op submodule checks are not summarized as pulls.
# =============================================================================

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${TEST_ROOT}/modules/git-operations.sh"

REPO_STATUSES[0]="submodule_updates"
REPO_MESSAGES[0]=""
set_submodule_update_classification 0 true false "Submodules already in sync"
if [ "${REPO_STATUSES[0]}" != "up_to_date" ]; then
    printf '%s\n' "No-op submodule result was incorrectly classified as pulled." >&2
    exit 1
fi

set_submodule_update_classification 0 true true "Updated 1 submodule(s)"
if [ "${REPO_STATUSES[0]}" != "pulled" ]; then
    printf '%s\n' "Changed submodule result was not classified as pulled." >&2
    exit 1
fi

printf '%s\n' "Bash submodule summary classification passed."
