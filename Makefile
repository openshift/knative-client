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
TEST_IMAGES=$(shell find -L ./test/test_images -mindepth 1 -maxdepth 1 -type d)
TEST=
DOCKER_REPO_OVERRIDE=

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

test-install:
	go install $(TEST_IMAGES)
.PHONY: test-install

test-images:
	for img in $(TEST_IMAGES); do \
		KO_DOCKER_REPO=$(DOCKER_REPO_OVERRIDE) ko resolve --tags=latest -RBf $$img/ ; \
	done
.PHONY: test-images

test-unit:
	./hack/build.sh -t
.PHONY: test-unit

test-e2e:
	./openshift/e2e-tests-openshift.sh
.PHONY: test-e2e

# Run make DOCKER_REPO_OVERRIDE=<your_repo> test-e2e-local if test images are available
# in the given repository. Make sure you first build and push them there by running `make test-images`.
# Run make BRANCH=<ci_promotion_name> test-e2e-local if test images from the latest CI
# build for this branch should be used. Example: `make BRANCH=knative-v0.17.2 test-e2e-local`.
# If neither DOCKER_REPO_OVERRIDE nor BRANCH are defined the tests will use test images
# from the last nightly build.
# If TEST is defined then only the single test will be run.
test-e2e-local:
	./openshift/e2e-tests-local.sh $(TEST)
.PHONY: test-e2e-local

# Generates a ci-operator configuration for a specific branch.
generate-ci-config:
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) > ci-operator-config.yaml
.PHONY: generate-ci-config
