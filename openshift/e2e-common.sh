#!/usr/bin/env bash

# Copyright 2019 The OpenShift Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

readonly ROOT_DIR=$(dirname $0)/..
source ${ROOT_DIR}/vendor/knative.dev/hack/library.sh
source ${ROOT_DIR}/vendor/knative.dev/hack/e2e-tests.sh

readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"
readonly SERVING_NAMESPACE="knative-serving"
readonly SERVING_INGRESS_NAMESPACE="knative-serving-ingress"
readonly EVENTING_NAMESPACE="knative-eventing"
readonly E2E_TIMEOUT="60m"
readonly OLM_NAMESPACE="openshift-marketplace"

# if you want to setup the nightly serving/eventing, set `release-next` OR
# set release branch name for example: release-v0.19.1
readonly SERVING_BRANCH="release-next"
# Pin the version due to issue in current nightly version
readonly EVENTING_BRANCH="release-v0.19.2"

# Determine if we're running locally or in CI.
if [ -n "$OPENSHIFT_BUILD_NAMESPACE" ]; then
  readonly TEST_IMAGE_TEMPLATE="${IMAGE_FORMAT//\$\{component\}/knative-client-test-{{.Name}}}"
elif [ -n "$DOCKER_REPO_OVERRIDE" ]; then
  readonly TEST_IMAGE_TEMPLATE="${DOCKER_REPO_OVERRIDE}/{{.Name}}"
elif [ -n "$BRANCH" ]; then
  readonly TEST_IMAGE_TEMPLATE="registry.svc.ci.openshift.org/openshift/${BRANCH}:knative-client-test-{{.Name}}"
elif [ -n "$TEMPLATE" ]; then
  readonly TEST_IMAGE_TEMPLATE="$TEMPLATE"
else
  readonly TEST_IMAGE_TEMPLATE="registry.svc.ci.openshift.org/openshift/knative-nightly:knative-client-test-{{.Name}}"
fi

env

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

build_knative_client() {
  failed=0
  # run this cross platform build to ensure all the checks pass (as this is done while building artifacts)
  ./hack/build.sh -x || failed=1

  if [[ $failed -eq 0 ]]; then
    mv kn-linux-amd64 kn
  fi

  return $failed
}

run_unit_tests() {
  failed=0
  go test -v ./cmd/... ./pkg/... || failed=1
  return $failed
}

run_client_e2e_tests(){
  local tags=$1
  local test_name=${2:-}

  header "Running e2e tests"
  local failed=0
  # Add local dir to have access to built kn
  export PATH=$PATH:${REPO_ROOT_DIR}
  export GO111MODULE=on
  # In CI environment GOFLAGS is set to '-mod=vendor', unsetting it and providing explicit flag below
  # while invoking go e2e tests. Unsetting to keep using -mod=vendor irrespective of whether GOFLAGS is set or not.
  # Ideally this should be overridden but see https://github.com/golang/go/issues/35827
  unset GOFLAGS

  # Add anyuid scc to all authenticated users so e2e tests for --user flag can user any user id
  oc adm policy add-scc-to-group anyuid system:authenticated

  local run_append=""
  if [ -n "${test_name}" ]; then
    run_append="-run ^(${test_name})$"
  fi
  if [ -n "${tags}" ]; then
    run_append="${run_append} -tags e2e,${tags}"
  else
    run_append="${run_append} -tags e2e"
  fi

  go test \
    ./test/e2e \
    -v -timeout=$E2E_TIMEOUT -mod=vendor \
    --imagetemplate $TEST_IMAGE_TEMPLATE \
    ${run_append} || failed=$?

  return $failed
}

# Waits until all pods are running in the given namespace.
# Parameters: $1 - namespace.
wait_until_pods_running() {
  echo -n "Waiting until all pods in namespace $1 are up"
  for i in {1..150}; do  # timeout after 5 minutes
    local pods="$(kubectl get pods --no-headers -n $1 2>/dev/null)"
    # All pods must be running
    local not_running=$(echo "${pods}" | grep -v Running | grep -v Completed | wc -l)
    if [[ -n "${pods}" && ${not_running} -eq 0 ]]; then
      local all_ready=1
      while read pod ; do
        local status=(`echo -n ${pod} | cut -f2 -d' ' | tr '/' ' '`)
        # All containers must be ready
        [[ -z ${status[0]} ]] && all_ready=0 && break
        [[ -z ${status[1]} ]] && all_ready=0 && break
        [[ ${status[0]} -lt 1 ]] && all_ready=0 && break
        [[ ${status[1]} -lt 1 ]] && all_ready=0 && break
        [[ ${status[0]} -ne ${status[1]} ]] && all_ready=0 && break
      done <<< "$(echo "${pods}" | grep -v Completed)"
      if (( all_ready )); then
        echo -e "\nAll pods are up:\n${pods}"
        return 0
      fi
    fi
    echo -n "."
    sleep 2
  done
  echo -e "\n\nERROR: timeout waiting for pods to come up\n${pods}"
  return 1
}

create_knative_namespace(){
  local COMPONENT="knative-$1"

  cat <<-EOF | oc apply -f -
	apiVersion: v1
	kind: Namespace
	metadata:
	  name: ${COMPONENT}
	EOF
}

install_knative_serving_branch() {
  local branch=$1
  local failed=0
  header "Installing Knative Serving from openshift/knative-serving branch $branch"
  rm -rf /tmp/knative-serving
  git clone --branch $branch https://github.com/openshift/knative-serving.git /tmp/knative-serving || return 1
  pushd /tmp/knative-serving

  source "openshift/e2e-common.sh"
  IMAGE_FORMAT='registry.svc.ci.openshift.org/openshift/knative-nightly:${component}' install_knative || failed=1
  popd
  return $failed
}


install_knative_eventing_branch() {
  local branch=$1

  header "Installing Knative Eventing from openshift/knative-eventing branch $branch"
  rm -rf /tmp/knative-eventing
  git clone --branch $branch https://github.com/openshift/knative-eventing.git /tmp/knative-eventing || return 1
  pushd /tmp/knative-eventing/

  create_knative_namespace eventing

  cat openshift/release/knative-eventing-ci.yaml > ci
  cat openshift/release/knative-eventing-mtbroker-ci.yaml >> ci

  oc apply -f ci
  rm ci

  # Wait for 5 pods to appear first
  timeout 900 '[[ $(oc get pods -n $EVENTING_NAMESPACE --no-headers | wc -l) -lt 5 ]]' || return 1
  wait_until_pods_running $EVENTING_NAMESPACE || return 1
  header "Knative Eventing installed successfully"
  popd
}

# Add to exec script if needed
resources_debug() {
  echo ">> Check resources"
  echo ">> - meminfo:"
  cat /proc/meminfo
  echo ">> - memory.limit_in_bytes"
  cat /sys/fs/cgroup/memory/memory.limit_in_bytes
  echo ">> - cpu.cfs_period_us"
  cat /sys/fs/cgroup/cpu/cpu.cfs_period_us
  echo ">> - cpu.cfs_quota_us"
  cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us
}
