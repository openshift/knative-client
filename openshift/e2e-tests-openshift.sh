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

source $(dirname $0)/../vendor/knative.dev/test-infra/scripts/library.sh
source $(dirname $0)/../vendor/knative.dev/test-infra/scripts/e2e-tests.sh

set -x

readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"
readonly SERVING_NAMESPACE="knative-serving"
readonly SERVICEMESH_NAMESPACE="knative-serving-ingress"
readonly E2E_TIMEOUT="60m"
readonly OLM_NAMESPACE="openshift-marketplace"
readonly EVENTING_NAMESPACE="knative-eventing"
readonly EVENTING_CATALOGSOURCE="https://raw.githubusercontent.com/openshift/knative-eventing/master/openshift/olm/knative-eventing.catalogsource.yaml"
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

function create_namespace(){
  cat <<-EOF | oc apply -f -
	apiVersion: v1
	kind: Namespace
	metadata:
	  name: $1
	EOF
}

function scale_up_workers(){
  local cluster_api_ns="openshift-machine-api"

  oc get machineset -n ${cluster_api_ns} --show-labels

  # Get the name of the first machineset that has at least 1 replica
  local machineset=$(oc get machineset -n ${cluster_api_ns} -o custom-columns="name:{.metadata.name},replicas:{.spec.replicas}" | grep " 1" | head -n 1 | awk '{print $1}')
  # Bump the number of replicas to 6 (+ 1 + 1 == 8 workers)
  oc patch machineset -n ${cluster_api_ns} ${machineset} -p '{"spec":{"replicas":6}}' --type=merge
  wait_until_machineset_scales_up ${cluster_api_ns} ${machineset} 6
}

# Waits until the machineset in the given namespaces scales up to the
# desired number of replicas
# Parameters: $1 - namespace
#             $2 - machineset name
#             $3 - desired number of replicas
function wait_until_machineset_scales_up() {
  echo -n "Waiting until machineset $2 in namespace $1 scales up to $3 replicas"
  for i in {1..150}; do  # timeout after 15 minutes
    local available=$(oc get machineset -n $1 $2 -o jsonpath="{.status.availableReplicas}")
    if [[ ${available} -eq $3 ]]; then
      echo -e "\nMachineSet $2 in namespace $1 successfully scaled up to $3 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo - "\n\nError: timeout waiting for machineset $2 in namespace $1 to scale up to $3 replicas"
  return 1
}

# Waits until the given hostname resolves via DNS
# Parameters: $1 - hostname
function wait_until_hostname_resolves() {
  echo -n "Waiting until hostname $1 resolves via DNS"
  for i in {1..150}; do  # timeout after 15 minutes
    local output="$(host -t a $1 | grep 'has address')"
    if [[ -n "${output}" ]]; then
      echo -e "\n${output}"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo -e "\n\nERROR: timeout waiting for hostname $1 to resolve via DNS"
  return 1
}

function install_serverless(){
  header "Installing Serverless Operator"
  git clone https://github.com/openshift-knative/serverless-operator.git /tmp/serverless-operator
  # unset OPENSHIFT_BUILD_NAMESPACE as its used in serverless-operator's CI environment as a switch
  # to use CI built images, we want pre-built images of k-s-o and k-o-i
  unset OPENSHIFT_BUILD_NAMESPACE
  /tmp/serverless-operator/hack/install.sh || return 1
  header "Serverless Operator installed successfully"
}

function install_knative_eventing(){
  header "Installing Knative Eventing"

  create_namespace $EVENTING_NAMESPACE
  oc apply -n $OLM_NAMESPACE -f $EVENTING_CATALOGSOURCE
  timeout 900 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c knative-eventing) -eq 0 ]]' || return 1
  wait_until_pods_running $OLM_NAMESPACE || return 1

  # Deploy Knative Operators Eventing
  deploy_knative_operator eventing KnativeEventing || return 1

  # Wait for 6 pods to appear first
  timeout 900 '[[ $(oc get pods -n $EVENTING_NAMESPACE --no-headers | wc -l) -lt 6 ]]' || return 1
  wait_until_pods_running $EVENTING_NAMESPACE || return 1

  header "Knative Eventing installed successfully"
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

  go_test_e2e -timeout=$E2E_TIMEOUT -mod=vendor ./test/e2e || fail_test
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


echo ">> Check resources"
echo ">> - meminfo:"
cat /proc/meminfo
echo ">> - memory.limit_in_bytes"
cat /sys/fs/cgroup/memory/memory.limit_in_bytes
echo ">> - cpu.cfs_period_us"
cat /sys/fs/cgroup/cpu/cpu.cfs_period_us
echo ">> - cpu.cfs_quota_us"
cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us

scale_up_workers || exit 1

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_serverless || failed=1

(( !failed )) && install_knative_eventing || failed=1

(( !failed )) && run_e2e_tests || failed=1

(( failed )) && exit 1

success
