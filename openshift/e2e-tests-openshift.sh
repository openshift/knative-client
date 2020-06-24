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
source ${ROOT_DIR}/scripts/test-infra/library.sh
source ${ROOT_DIR}/scripts/test-infra/e2e-tests.sh

set -x

readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"
readonly SERVING_NAMESPACE="knative-serving"
readonly EVENTING_NAMESPACE="knative-eventing"
readonly E2E_TIMEOUT="60m"
readonly OLM_NAMESPACE="openshift-marketplace"
readonly EVENTING_CATALOGSOURCE="https://raw.githubusercontent.com/openshift/knative-eventing/master/openshift/olm/knative-eventing.catalogsource.yaml"
readonly OPERATOR_CLONE_PATH="/tmp/serverless-operator"

env

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function install_serverless(){
  header "Installing Serverless Operator"
  git clone https://github.com/openshift-knative/serverless-operator.git ${OPERATOR_CLONE_PATH} || return 1
  # unset OPENSHIFT_BUILD_NAMESPACE as its used in serverless-operator's CI environment as a switch
  # to use CI built images, we want pre-built images of k-s-o and k-o-i
  unset OPENSHIFT_BUILD_NAMESPACE
  ${OPERATOR_CLONE_PATH}/hack/install.sh || return 1
  header "Serverless Operator installed successfully"
}

function teardown_serverless(){
  header "Tear down Serverless Operator"
  ${OPERATOR_CLONE_PATH}/hack/teardown.sh || return 1
  header "Serverless Operator uninstalled successfully"
}


function deploy_knative_operator(){
  local COMPONENT="knative-$1"
  local API_GROUP=$1
  local KIND=$2

  if oc get crd operatorgroups.operators.coreos.com >/dev/null 2>&1; then
    cat <<-EOF | oc apply -f -
	apiVersion: operators.coreos.com/v1
	kind: OperatorGroup
	metadata:
	  name: ${COMPONENT}
	  namespace: ${COMPONENT}
	EOF
  fi
  cat <<-EOF | oc apply -f -
	apiVersion: operators.coreos.com/v1alpha1
	kind: Subscription
	metadata:
	  name: ${COMPONENT}-subscription
	  generateName: ${COMPONENT}-
	  namespace: ${COMPONENT}
	spec:
	  source: ${COMPONENT}-operator
	  sourceNamespace: $OLM_NAMESPACE
	  name: ${COMPONENT}-operator
	  channel: alpha
	EOF

  # # Wait until the server knows about the Install CRD before creating
  # # an instance of it below
  timeout 60 '[[ $(oc get crd knative${API_GROUP}s.${API_GROUP}.knative.dev -o jsonpath="{.status.acceptedNames.kind}" | grep -c $KIND) -eq 0 ]]' || return 1
}

function build_knative_client() {
  failed=0
  # run this cross platform build to ensure all the checks pass (as this is done while building artifacts)
  ./hack/build.sh -x || failed=1

  if [[ $failed -eq 0 ]]; then
    mv kn-linux-amd64 kn
  fi

  return $failed
}

function run_e2e_tests(){
  TAGS=$1
  header "Running e2e tests"
  failed=0
  # Add local dir to have access to built kn
  export PATH=$PATH:${REPO_ROOT_DIR}
  export GO111MODULE=on
  # In CI environment GOFLAGS is set to '-mod=vendor', unsetting it and providing explicit flag below
  # while invoking go e2e tests. Unsetting to keep using -mod=vendor irrespective of whether GOFLAGS is set or not.
  # Ideally this should be overridden but see https://github.com/golang/go/issues/35827
  unset GOFLAGS

  # Add anyuid scc to all authenticated users so e2e tests for --user flag can user any user id
  oc adm policy add-scc-to-group anyuid system:authenticated

  go test \
    ./test/e2e \
    -v -timeout=$E2E_TIMEOUT -mod=vendor \
    -tags="e2e $TAGS" || fail_test

  return $failed
}

# Waits until all pods are running in the given namespace.
# Parameters: $1 - namespace.
function wait_until_pods_running() {
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

function install_serverless_1_6(){
  header "Installing Serverless Operator"
  git clone --branch release-1.6 https://github.com/openshift-knative/serverless-operator.git /tmp/serverless-operator-16
  # unset OPENSHIFT_BUILD_NAMESPACE as its used in serverless-operator's CI environment as a switch
  # to use CI built images, we want pre-built images of k-s-o and k-o-i
  unset OPENSHIFT_BUILD_NAMESPACE
  /tmp/serverless-operator-16/hack/install.sh || return 1
  header "Serverless Operator installed successfully"
}

function create_knative_namespace(){
  local COMPONENT="knative-$1"

  cat <<-EOF | oc apply -f -
	apiVersion: v1
	kind: Namespace
	metadata:
	  name: ${COMPONENT}
	EOF
}

function deploy_knative_operator(){
  local COMPONENT="knative-$1"
  local API_GROUP=$1
  local KIND=$2

  cat <<-EOF | oc apply -f -
	apiVersion: v1
	kind: Namespace
	metadata:
	  name: ${COMPONENT}
	EOF
  if oc get crd operatorgroups.operators.coreos.com >/dev/null 2>&1; then
    cat <<-EOF | oc apply -f -
	apiVersion: operators.coreos.com/v1
	kind: OperatorGroup
	metadata:
	  name: ${COMPONENT}
	  namespace: ${COMPONENT}
	EOF
  fi
  cat <<-EOF | oc apply -f -
	apiVersion: operators.coreos.com/v1alpha1
	kind: Subscription
	metadata:
	  name: ${COMPONENT}-subscription
	  generateName: ${COMPONENT}-
	  namespace: ${COMPONENT}
	spec:
	  source: ${COMPONENT}-operator
	  sourceNamespace: $OLM_NAMESPACE
	  name: ${COMPONENT}-operator
	  channel: alpha
	EOF

  # # Wait until the server knows about the Install CRD before creating
  # # an instance of it below
  timeout 60 '[[ $(oc get crd knative${API_GROUP}s.${API_GROUP}.knative.dev -o jsonpath="{.status.acceptedNames.kind}" | grep -c $KIND) -eq 0 ]]' || return 1
}

function install_knative_eventing(){
  header "Installing Knative Eventing"

  create_knative_namespace eventing

  # oc apply -n $OLM_NAMESPACE -f knative-eventing.catalogsource-ci.yaml
  oc apply -n $OLM_NAMESPACE -f $EVENTING_CATALOGSOURCE
  timeout 900 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c knative-eventing) -eq 0 ]]' || return 1
  wait_until_pods_running $OLM_NAMESPACE

  # Deploy Knative Operators Eventing
  deploy_knative_operator eventing KnativeEventing

  # Wait for 5 pods to appear first
  timeout 900 '[[ $(oc get pods -n $EVENTING_NAMESPACE --no-headers | wc -l) -lt 5 ]]' || return 1
  wait_until_pods_running $EVENTING_NAMESPACE || return 1

  # Assert that there are no images used that are not CI images (which should all be using the $INTERNAL_REGISTRY)
  # (except for the knative-eventing-operator)
  #oc get pod -n knative-eventing -o yaml | grep image: | grep -v knative-eventing-operator | grep -v ${INTERNAL_REGISTRY} && return 1 || true
}

echo ">> Check resources"
echo ">> - meminfo:"
cat /proc/meminfo
echo ">> - memory.limit_in_bytes"
cat /sys/fs/cgroup/memory/memory.limit_in_bytes
echo ">> - cpu.cfs_period_us"
cat /sys/fs/cgroup/cpu/cpu.cfs_period_us
echo ">> - cpu.cfs_quota_us"
cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_serverless || failed=1

(( !failed )) && run_e2e_tests serving || failed=1

(( !failed )) && teardown_serverless || failed=1

(( !failed )) && install_serverless_1_6 || failed=1

(( !failed )) && install_knative_eventing || failed=1

(( !failed )) && run_e2e_tests eventing || failed=1

(( failed )) && exit 1

success
