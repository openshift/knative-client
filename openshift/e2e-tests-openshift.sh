#!/usr/bin/env bash
# The script prepares Serving/Eventing instances on OpenShift and executes E2E tests

source "$(dirname "$0")/e2e-common.sh"

set +x

failed=0

# Build binary
(( !failed )) && build_knative_client || failed=1
# Serving setup & tests
(( !failed )) && install_knative_serving_branch "${SERVING_BRANCH}" || failed=1
#TODO: TEMP SKIPPED
#(( !failed )) && run_e2e_tests serving || failed=1
# Eventing setup & tests
(( !failed )) && install_knative_eventing_branch "${EVENTING_BRANCH}" || failed=1
#TODO: TEMP SKIPPED
#(( !failed )) && run_e2e_tests eventing || failed=1

(( !failed )) && install_strimzi || failed=1
(( !failed )) && install_knative_kafka "${EVENTING_CONTRIB_BRANCH}" || failed=1
(( !failed )) && run_e2e_tests "" "TestSourceKafka" || failed=1

(( failed )) && exit 1

success
