#!/usr/bin/env bash
# The script prepares Serving/Eventing instances on OpenShift and executes E2E tests

source "$(dirname "$0")/e2e-common.sh"

set -Eeuox pipefail

failed=0

# Build binary
(( !failed )) && build_knative_client || failed=1
# Run unit tests
 (( !failed )) && run_unit_tests || failed=1
# Serverless operator setup & tests
(( !failed )) && install_serverless_operator_branch "release-1.16" || failed=1
(( !failed )) && run_client_e2e_tests serving || failed=1
(( !failed )) && run_client_e2e_tests eventing || failed=1

(( failed )) && exit 1

success
