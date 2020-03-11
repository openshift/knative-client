#This makefile is used by ci-operator

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

CGO_ENABLED=0
GOOS=linux

install: build
	cp ./kn $(GOPATH)/bin
.PHONY: install

build:
	./hack/build.sh -f
.PHONY: build

build-cross:
	./hack/build.sh -x
.PHONY: build-cross

build-cross-package: build-cross
	./package_cliartifacts.sh
.PHONY: build-cross-package

test-unit:
	./hack/build.sh -t
.PHONY: test-unit

test-e2e:
	./openshift/e2e-tests-openshift.sh
.PHONY: test-e2e

# Generates a ci-operator configuration for a specific branch.
generate-ci-config:
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) > ci-operator-config.yaml
.PHONY: generate-ci-config
