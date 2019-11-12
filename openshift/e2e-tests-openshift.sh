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

readonly SERVING_RELEASE="release-v0.8.1"
readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"
readonly SERVING_NAMESPACE="knative-serving"
readonly SERVICEMESH_NAMESPACE="istio-system"
readonly E2E_TIMEOUT="60m"
readonly E2E_PARALLEL="1"
readonly CS_NS="openshift-marketplace"
readonly OPERATOR_NS="openshift-operators"
env

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

# Waits until the configmap in the given namespace contains the
# desired content.
# Parameters: $1 - namespace
#             $2 - configmap name
#             $3 - desired content
function wait_until_configmap_contains() {
  echo -n "Waiting until configmap $1/$2 contains '$3'"
  for _ in {1..180}; do  # timeout after 3 minutes
    local output="$(oc -n "$1" get cm "$2" -oyaml | grep "$3")"
    if [[ -n "${output}" ]]; then
      echo -e "\n${output}"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo -e "\n\nERROR: timeout waiting for configmap $1/$2 to contain '$3'"
  return 1
}

# Loops until duration (car) is exceeded or command (cdr) returns non-zero
function timeout() {
  SECONDS=0; TIMEOUT=$1; shift
  while eval $*; do
    sleep 5
    [[ $SECONDS -gt $TIMEOUT ]] && echo "ERROR: Timed out" && return 1
  done
  return 0
}

function install_servicemesh(){
  header "Installing ServiceMesh"

  # Install the ServiceMesh Operator
  oc apply -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/operator-install.yaml

  # Wait for the istio-operator pod to appear
  timeout 900 '[[ $(oc get pods -n openshift-operators | grep -c istio-operator) -eq 0 ]]' || return 1

  # Wait until the Operator pod is up and running
  wait_until_pods_running openshift-operators || return 1

  # Deploy ServiceMesh
  oc new-project $SERVICEMESH_NAMESPACE
  oc apply -n $SERVICEMESH_NAMESPACE -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/controlplane-install.yaml
  cat <<EOF | oc apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: ${SERVICEMESH_NAMESPACE}
spec:
  members:
  - ${SERVING_NAMESPACE}
  - kne2etests0
  - kne2etests1
  - kne2etests2
  - kne2etests3
  - kne2etests4
  - kne2etests5
EOF

  # Wait for the ingressgateway pod to appear.
  timeout 900 '[[ $(oc get pods -n $SERVICEMESH_NAMESPACE | grep -c istio-ingressgateway) -eq 0 ]]' || return 1

  wait_until_service_has_external_ip $SERVICEMESH_NAMESPACE istio-ingressgateway || fail_test "Ingress has no external IP"
  wait_until_hostname_resolves "$(kubectl get svc -n $SERVICEMESH_NAMESPACE istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

  wait_until_pods_running $SERVICEMESH_NAMESPACE

  header "ServiceMesh installed successfully"
}

function install_knative_serving(){
  header "Installing Knative serving"

  oc new-project $SERVING_NAMESPACE

  # Deploy Serverless Operator
  deploy_serverless_operator

  # Wait for the CRD to appear
  timeout 900 '[[ $(oc get crd | grep -c knativeservings) -eq 0 ]]' || return 1

  # Install Knative Serving
  cat <<-EOF | oc apply -f -
apiVersion: serving.knative.dev/v1alpha1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: ${SERVING_NAMESPACE}
EOF

  # Wait for 6 pods to appear first
  timeout 900 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 6 ]]' || return

  wait_until_pods_running $SERVING_NAMESPACE || return 1

  header "Knative Serving installed successfully"
}

function deploy_serverless_operator(){
  git clone https://github.com/openshift-knative/serverless-operator.git /tmp/serverless-operator
  /tmp/serverless-operator/hack/catalog.sh | oc apply -n $CS_NS -f -
  cat <<-EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: serverless-operator-sub
  generateName: serverless-operator-
  namespace: $OPERATOR_NS
spec:
  source: serverless-operator
  sourceNamespace: $CS_NS
  name: serverless-operator
  channel: techpreview
EOF
}

function enable_knative_interaction_with_registry() {
  local configmap_name=config-service-ca
  local cert_name=service-ca.crt
  local mount_path=/var/run/secrets/kubernetes.io/servicecerts

  oc -n $SERVING_NAMESPACE create configmap $configmap_name
  oc -n $SERVING_NAMESPACE annotate configmap $configmap_name service.alpha.openshift.io/inject-cabundle="true"
  wait_until_configmap_contains $SERVING_NAMESPACE $configmap_name $cert_name
  oc -n $SERVING_NAMESPACE set volume deployment/controller --add --name=service-ca --configmap-name=$configmap_name --mount-path=$mount_path
  oc -n $SERVING_NAMESPACE set env deployment/controller SSL_CERT_FILE=$mount_path/$cert_name
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
  go_test_e2e -timeout=$E2E_TIMEOUT -parallel=$E2E_PARALLEL ./test/e2e || fail_test
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

function delete_knative_openshift() {
  echo ">> Bringing down Knative Serving"
  oc delete --ignore-not-found=true -f openshift/serverless/operator-install.yaml
  oc delete --ignore-not-found=true project $SERVING_NAMESPACE
}

function delete_test_namespace(){
  echo ">> Deleting test namespaces"
  oc delete project --ignore-not-found=true kne2etests0 kne2etests1 kne2etests2 kne2etests3 kne2etests4 kne2etests5
}

function delete_service_mesh(){
  echo ">> Bringin down Service Mesh"
  oc delete --ignore-not-found=true -n $SERVICEMESH_NAMESPACE -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/controlplane-install.yaml
  oc delete --ignore-not-found=true -f https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE/openshift/servicemesh/operator-install.yaml
}

function teardown() {
  delete_test_namespace
  delete_service_mesh
  delete_knative_openshift
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

(( !failed )) && install_servicemesh || failed=1

(( !failed )) && install_knative_serving || failed=1

(( !failed )) && run_e2e_tests || failed=1

teardown

(( failed )) && exit 1

success
