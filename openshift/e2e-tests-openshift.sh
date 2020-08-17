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
readonly E2E_TIMEOUT="60m"

# TODO: change this to release-1.9 when the branch is setup on the operator repo
readonly OPERATOR_BRANCH="master"

env

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
    -tags="e2e $TAGS" || fail_test

  return $failed
}

install_serverless_operator_branch() {
  local branch=$1
  local clone_path="/tmp/serverless-operator"
  header "Installing Serverless Operator from branch: $branch"
  rm -rf $clone_path
  git clone --branch $branch https://github.com/openshift-knative/serverless-operator.git $clone_path
  pushd $clone_path
  make install || return 1
  header "Serverless Operator installed successfully"
  popd
}

failed=0

(( !failed )) && build_knative_client || failed=1

(( !failed )) && install_serverless_operator_branch "${OPERATOR_BRANCH}" || failed=1

(( !failed )) && run_e2e_tests || failed=1

(( failed )) && exit 1

success
