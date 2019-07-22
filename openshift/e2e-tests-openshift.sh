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

source $(dirname $0)/../vendor/github.com/knative/test-infra/scripts/library.sh
source $(dirname $0)/../vendor/github.com/knative/test-infra/scripts/e2e-tests.sh

set -x

readonly TEST_NAMESPACE=client-tests
readonly TEST_NAMESPACE_ALT=client-tests-alt
readonly OLM_NAMESPACE="openshift-operator-lifecycle-manager"
readonly SERVING_RELEASE_BRANCH="release-v0.6.0"
readonly SERVING_RELEASE_TAG="v0.6.0"
readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"
readonly SERVING_NAMESPACE=knative-serving

env

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

function install_knative(){
  header "Installing Knative serving"

  echo ">> Patching Knative Serving CatalogSource to reference serving release ${SERVING_RELEASE_BRANCH}"
  RELEASE_YAML="https://raw.githubusercontent.com/openshift/knative-serving/${SERVING_RELEASE_BRANCH}/openshift/release/knative-serving-${SERVING_RELEASE_TAG}.yaml"
  sed "s|--filename=.*|--filename=${RELEASE_YAML}|"  openshift/olm/knative-serving.catalogsource.yaml > knative-serving.catalogsource-ci.yaml

  # Install CatalogSources in OLM namespace
  oc apply -n $OLM_NAMESPACE -f knative-serving.catalogsource-ci.yaml
  timeout 900 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c knative) -eq 0 ]]' || return 1
  wait_until_pods_running $OLM_NAMESPACE

  # Deploy Knative Operators Serving
  deploy_knative_operator serving KnativeServing

  # Wait for 6 pods to appear first
  timeout 900 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 6 ]]' || return 1
  wait_until_pods_running knative-serving || return 1

  # Wait for 2 pods to appear first
  timeout 900 '[[ $(oc get pods -n istio-system --no-headers | wc -l) -lt 2 ]]' || return 1
  wait_until_service_has_external_ip istio-system istio-ingressgateway || fail_test "Ingress has no external IP"

  wait_until_hostname_resolves $(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

  header "Knative serving Installed successfully"
}

function deploy_knative_operator(){
  local COMPONENT="knative-$1"
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
  cat <<-EOF | oc apply -f -
  apiVersion: serving.knative.dev/v1alpha1
  kind: $KIND
  metadata:
    name: ${COMPONENT}
    namespace: ${COMPONENT}
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

function create_test_namespace(){
  oc new-project $TEST_NAMESPACE
  oc new-project $TEST_NAMESPACE_ALT
  oc adm policy add-scc-to-user privileged -z default -n $TEST_NAMESPACE
  oc adm policy add-scc-to-user privileged -z default -n $TEST_NAMESPACE_ALT
}

function build_knative_client() {
  failed=0
  ./hack/build.sh -f || failed=1
  return $failed
}

function run_e2e_tests(){
  header "Running tests"
  failed=0

  # adding the basic workflow tests for now
  # TODO: Link the integration tests written in go here once the PR is merged upstream

  ./kn service create svc1 --async --image $KN_DEFAULT_TEST_IMAGE -e TARGET=Knative || fail_test
  ./kn service create hello --wait-timeout 120 --image $KN_DEFAULT_TEST_IMAGE -e TARGET=Knative || fail_test
  ./kn service list hello || fail_test
  ./kn service update hello --env TARGET=kn || fail_test
  ./kn revision list hello || fail_test
  ./kn service list || fail_test
  ./kn service create hello --wait-timeout 120 --force --image $KN_DEFAULT_TEST_IMAGE -e TARGET=Awesome || fail_test
  ./kn service create foo --wait-timeout 120 --force --image $KN_DEFAULT_TEST_IMAGE -e TARGET=foo || fail_test
  ./kn revision list || fail_test
  ./kn service list || fail_test
  ./kn service describe hello || fail_test
  ./kn service describe svc1 || fail_test
  ./kn route list || fail_test
  ./kn service delete hello || fail_test
  ./kn service delete foo || fail_test
  ./kn service list | grep -q svc1 || fail_test
  ./kn service delete svc1 || fail_test

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
  oc delete --ignore-not-found=true -n $OLM_NAMESPACE -f knative-serving.catalogsource-ci.yaml
  oc delete --ignore-not-found=true project $SERVING_NAMESPACE
}

function delete_test_namespace(){
  echo ">> Deleting test namespaces"
  oc delete project $TEST_NAMESPACE
  oc delete project $TEST_NAMESPACE_ALT
}

function teardown() {
  delete_test_namespace
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

create_test_namespace || exit 1

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_knative || failed=1

(( !failed )) && run_e2e_tests || failed=1

teardown

(( failed )) && exit 1

success
