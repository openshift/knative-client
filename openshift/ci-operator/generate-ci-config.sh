#!/bin/bash

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

branch=${1-'master'}
version=$(echo ${branch} | cut -d '-' -f 2)
tag=${version:-'master'}

cat <<EOF
base_images:
  base:
    name: ubi-minimal
    namespace: ocp
    tag: "8"
binary_build_commands: |
  TAG=${tag} make install
  TAG=${tag} make build-cross
build_root:
  project_image:
    dockerfile_path: openshift/ci-operator/build-image/Dockerfile
canonical_go_repository: github.com/knative/client
images:
- dockerfile_path: openshift/ci-operator/knative-images/client/Dockerfile
  from: base
  inputs:
    bin:
      paths:
      - destination_dir: .
        source_path: /go/bin/kn
  to: knative-client
- dockerfile_path: openshift/ci-operator/knative-images/client/Dockerfile.cliartifacts
  inputs:
    bin:
      paths:
      - destination_dir: .
        source_path: /go/src/github.com/knative/client/kn-linux-amd64
      - destination_dir: .
        source_path: /go/src/github.com/knative/client/kn-darwin-amd64
      - destination_dir: .
        source_path: /go/src/github.com/knative/client/kn-windows-amd64.exe
      - destination_dir: .
        source_path: /go/src/github.com/knative/client/LICENSE
      - destination_dir: .
        source_path: /go/src/github.com/knative/client/package_cliartifacts.sh
  to: kn-cli-artifacts
- dockerfile_path: openshift/ci-operator/knative-test-images/helloworld/Dockerfile
  from: base
  inputs:
    test-bin:
      paths:
      - destination_dir: .
        source_path: /go/bin/helloworld
  to: knative-client-test-helloworld
promotion:
  name: $branch
  namespace: openshift
resources:
  '*':
    requests:
      memory: 2Gi
tag_specification:
  name: "4.5"
  namespace: ocp
test_binary_build_commands: make test-install
tests:
- as: e2e-aws-ocp-45
  commands: make test-e2e
  openshift_installer_src:
    cluster_profile: aws
EOF
