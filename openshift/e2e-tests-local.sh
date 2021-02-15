#!/usr/bin/env bash
# The script executes E2E tests

source "$(dirname "$0")/e2e-common.sh"

set +x

failed=0

(( !failed )) && run_client_e2e_tests "" "${TEST}" || failed=1
(( failed )) && exit 1

success
