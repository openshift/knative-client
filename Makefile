#This makefile is used by ci-operator

CGO_ENABLED=0
GOOS=linux

build:
	./hack/build.sh
.PHONY: build

test-e2e:
	./openshift/e2e-tests-openshift.sh
.PHONY: test-e2e

# Generates a ci-operator configuration for a specific branch.
generate-ci-config:
	./openshift/ci-operator/generate-ci-config.sh $(BRANCH) > ci-operator-config.yaml
.PHONY: generate-ci-config
