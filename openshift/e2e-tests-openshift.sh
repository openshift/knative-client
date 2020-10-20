#!/usr/bin/env bash
# The script prepares Serving/Eventing instances on OpenShift and executes E2E tests

source "$(dirname "$0")/e2e-common.sh"

set +x

failed=0

# Build binary
(( !failed )) && build_knative_client || failed=1
# Serving setup & tests
(( !failed )) && install_knative_serving_branch "${SERVING_BRANCH}" || failed=1
(( !failed )) && run_e2e_tests serving || failed=1
# Eventing setup & tests
(( !failed )) && install_knative_eventing_branch "${EVENTING_BRANCH}" || failed=1
(( !failed )) && run_e2e_tests eventing || failed=1

(( failed )) && exit 1

success
