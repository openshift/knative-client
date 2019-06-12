#!/usr/bin/env bash

source $(dirname $0)/../test/e2e-common.sh
source $(dirname $0)/release/resolve.sh

set -x

readonly K8S_CLUSTER_OVERRIDE=$(oc config current-context | awk -F'/' '{print $2}')
readonly API_SERVER=$(oc config view --minify | grep server | awk -F'//' '{print $2}' | awk -F':' '{print $1}')
readonly INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-"image-registry.openshift-image-registry.svc:5000"}"
readonly USER=$KUBE_SSH_USER #satisfy e2e_flags.go#initializeFlags()
readonly OPENSHIFT_REGISTRY="${OPENSHIFT_REGISTRY:-"registry.svc.ci.openshift.org"}"
readonly INSECURE="${INSECURE:-"false"}"
readonly TEST_NAMESPACE=client-tests
readonly TEST_NAMESPACE_ALT=client-tests-alt
readonly CLIENT_NAMESPACE=knative-client
readonly OLM_NAMESPACE="openshift-operator-lifecycle-manager"
readonly SERVING_RELEASE_BRANCH="release-v0.6.0"
readonly KN_DEFAULT_TEST_IMAGE="gcr.io/knative-samples/helloworld-go"

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
  header "Installing Knative"

  echo ">> Patching Knative Serving CatalogSource to reference CI produced images"
  RELEASE_YAML="https://raw.githubusercontent.com/openshift/knative-serving/$SERVING_RELEASE_BRANCH/openshift/release/knative-serving-ci.yaml"
  sed "s|--filename=.*|--filename=${RELEASE_YAML}|"  openshift/olm/knative-serving.catalogsource.yaml > knative-serving.catalogsource-ci.yaml

  # Install CatalogSources in OLM namespace
  oc apply -n $OLM_NAMESPACE -f knative-serving.catalogsource-ci.yaml
  timeout 900 '[[ $(oc get pods -n $OLM_NAMESPACE | grep -c knative) -eq 0 ]]' || return 1
  wait_until_pods_running $OLM_NAMESPACE

  # Deploy Knative Operators Serving
  deploy_knative_operator serving

  # Wait for 6 pods to appear first
  timeout 900 '[[ $(oc get pods -n $SERVING_NAMESPACE --no-headers | wc -l) -lt 6 ]]' || return 1
  wait_until_pods_running knative-serving || return 1

  #enable_knative_interaction_with_registry

  # Wait for 2 pods to appear first
  timeout 900 '[[ $(oc get pods -n istio-system --no-headers | wc -l) -lt 2 ]]' || return 1
  wait_until_service_has_external_ip istio-system istio-ingressgateway || fail_test "Ingress has no external IP"

  wait_until_hostname_resolves $(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

  header "Knative Installed successfully"
}

function deploy_knative_operator(){
  local COMPONENT="knative-$1"

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
  kind: Install
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
  ./hack/build.sh || failed=1
  return $failed
}

function run_e2e_tests(){
  header "Running tests"
  failed=0

  # adding the basic workflow tests for now
  # TODO: Link the integration tests written in go here once the PR is merged upstream

  ./kn service create hello --image $KN_DEFAULT_TEST_IMAGE -e TARGET=Knative || failed=1
  sleep 5
  ./kn service get || failed=1
  ./kn service update hello --env TARGET=kn || failed=1
  sleep 3
  ./kn revision get || failed=1
  ./kn service get || failed=1
  ./kn service create hello --force --image $KN_DEFAULT_TEST_IMAGE -e TARGET=Awesome || failed=1
  ./kn service create foo --force --image $KN_DEFAULT_TEST_IMAGE -e TARGET=foo || failed=1
  sleep 5
  ./kn revision get || failed=1
  ./kn service get || failed=1
  ./kn service describe hello || failed=1
  ./kn service delete hello || failed=1
  ./kn service delete foo || failed=1

  return $failed
}

function delete_knative_openshift() {
  echo ">> Bringing down Knative Serving, Build and Pipeline"
  oc delete --ignore-not-found=true -n $OLM_NAMESPACE -f knative-serving.catalogsource-ci.yaml
  oc delete --ignore-not-found=true -f third_party/config/build/release.yaml
  oc delete --ignore-not-found=true -f third_party/config/pipeline/release.yaml

  oc delete project $SERVING_NAMESPACE
  oc delete project knative-build
  oc delete project knative-build-pipeline
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

create_test_namespace || exit 1

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_knative || failed=1

(( !failed )) && run_e2e_tests || failed=1

teardown

(( failed )) && exit 1

success
