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
readonly SERVING_INGRESS_NAMESPACE="knative-serving-ingress"
readonly EVENTING_NAMESPACE="knative-eventing"
readonly E2E_TIMEOUT="60m"
readonly OLM_NAMESPACE="openshift-marketplace"

# if you want to setup the nightly serving/eventing, set `release-next` below or else set release branch
readonly SERVING_BRANCH="release-v0.17.3"
readonly EVENTING_BRANCH="release-v0.17.2"

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

# Waits until the given hostname resolves via DNS
# Parameters: $1 - hostname
wait_until_hostname_resolves() {
  echo -n "Waiting until hostname $1 resolves via DNS"
  for _ in {1..150}; do  # timeout after 15 minutes
    local output
    output=$(host -t a "$1" | grep 'has address')
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

build_knative_client() {
  failed=0
  # run this cross platform build to ensure all the checks pass (as this is done while building artifacts)
  ./hack/build.sh -x || failed=1

  if [[ $failed -eq 0 ]]; then
    mv kn-linux-amd64 kn
  fi

  return $failed
}

run_e2e_tests(){
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
    --imagetemplate $TEST_IMAGE_TEMPLATE \
    -tags="e2e $TAGS" || fail_test

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

deploy_serverless_operator(){
  local name="serverless-operator"
  local operator_ns
  operator_ns=$(kubectl get og --all-namespaces | grep global-operators | awk '{print $1}')

  # Create configmap to use the latest manifest.
  oc create configmap ko-data-serving -n $operator_ns --from-file="openshift/release/knative-serving-ci.yaml"

  # Create eventing manifest. We don't want to do this, but upstream designed that knative-eventing dir is mandatory
  # when KO_DATA_PATH was overwritten.
  oc create configmap ko-data-eventing -n $operator_ns --from-file="openshift/release/knative-eventing-ci.yaml"

  # Create configmap to use the latest kourier.
  oc create configmap kourier-cm -n $operator_ns --from-file="third_party/kourier-latest/kourier.yaml"

  cat <<-EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${name}-subscription
  namespace: ${operator_ns}
spec:
  source: ${name}
  sourceNamespace: $OLM_NAMESPACE
  name: ${name}
  channel: "preview-4.6"
EOF
}

install_knative_serving_branch() {
  local branch=$1

  header "Installing Knative Serving from openshift/knative-serving branch $branch"
  rm -rf /tmp/knative-serving
  git clone --branch $branch https://github.com/openshift/knative-serving.git /tmp/knative-serving
  pushd /tmp/knative-serving

  oc new-project $SERVING_NAMESPACE

  export IMAGE_kourier="quay.io/3scale/kourier:v0.3.11"
  CATALOG_SOURCE="openshift/olm/knative-serving.catalogsource.yaml"

  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-queue|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-queue|g"                   ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-activator|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-activator|g"           ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-autoscaler|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-autoscaler|g"         ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-autoscaler-hpa|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-autoscaler-hpa|g" ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-webhook|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-webhook|g"               ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:knative-serving-controller|registry.svc.ci.openshift.org/openshift/knative-v0.17.3:knative-serving-controller|g"         ${CATALOG_SOURCE}

  envsubst < $CATALOG_SOURCE | oc apply -n $OLM_NAMESPACE -f -

  # Replace kourier's image with the latest ones from third_party/kourier-latest
  KOURIER_CONTROL=$(grep -w "gcr.io/knative-nightly/knative.dev/net-kourier/cmd/kourier" third_party/kourier-latest/kourier.yaml  | awk '{print $NF}')
  KOURIER_GATEWAY=$(grep -w "docker.io/maistra/proxyv2-ubi8" third_party/kourier-latest/kourier.yaml  | awk '{print $NF}')

  # TODO: Adding env variable manually until operator implments it. See SRVKS-610
  sed -i -e 's/value: "kourier-system"/value: "knative-serving-ingress"/g'  third_party/kourier-latest/kourier.yaml
  sed -i -e 's/kourier-control.knative-serving/kourier-control.knative-serving-ingress/g'  third_party/kourier-latest/kourier.yaml

  sed -i -e "s|docker.io/maistra/proxyv2-ubi8:.*|${KOURIER_GATEWAY}|g"                                        ${CATALOG_SOURCE}
  sed -i -e "s|registry.svc.ci.openshift.org/openshift/knative-.*:kourier|${KOURIER_CONTROL}|g"               ${CATALOG_SOURCE}

  # release-next branch keeps updating the latest manifest in knative-serving-ci.yaml for serving resources.
  # see: https://github.com/openshift/knative-serving/blob/release-next/openshift/release/knative-serving-ci.yaml
  # So mount the manifest and use it by KO_DATA_PATH env value.
  patch -u ${CATALOG_SOURCE} < openshift/olm/config_map.patch

  oc apply -n $OLM_NAMESPACE -f ${CATALOG_SOURCE}
  timeout 600 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c serverless) -eq 0 ]]' || return 1
  wait_until_pods_running $OLM_NAMESPACE

  # Deploy Serverless Operator
  deploy_serverless_operator

  # Wait for the CRD to appear
  timeout 600 '[[ $(oc get crd | grep -c knativeservings) -eq 0 ]]' || return 1

  # Install Knative Serving
  cat <<-EOF | oc apply -f -
apiVersion: operator.knative.dev/v1alpha1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: ${SERVING_NAMESPACE}
EOF

  # Wait for 4 pods to appear first
  timeout 600 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 4 ]]' || return 1
  wait_until_pods_running $SERVING_NAMESPACE || return 1

  wait_until_service_has_external_ip $SERVING_INGRESS_NAMESPACE kourier || fail_test "Ingress has no external IP"
  wait_until_hostname_resolves "$(kubectl get svc -n $SERVING_INGRESS_NAMESPACE kourier -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

  header "Knative Serving installed successfully"
  popd
}


install_knative_eventing_branch() {
  local branch=$1

  header "Installing Knative Eventing from openshift/knative-eventing branch $branch"
  rm -rf /tmp/knative-eventing
  git clone --branch $branch https://github.com/openshift/knative-eventing.git /tmp/knative-eventing
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


## Uncomment following lines if you are debugging and requiring respective info
#echo ">> Check resources"
#echo ">> - meminfo:"
#cat /proc/meminfo
#echo ">> - memory.limit_in_bytes"
#cat /sys/fs/cgroup/memory/memory.limit_in_bytes
#echo ">> - cpu.cfs_period_us"
#cat /sys/fs/cgroup/cpu/cpu.cfs_period_us
#echo ">> - cpu.cfs_quota_us"
#cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_knative_serving_branch "${SERVING_BRANCH}" || failed=1

(( !failed )) && run_e2e_tests serving || failed=1

(( !failed )) && install_knative_eventing_branch "${EVENTING_BRANCH}" || failed=1

(( !failed )) && run_e2e_tests eventing || failed=1

(( failed )) && exit 1

success
