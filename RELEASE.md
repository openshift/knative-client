## Crafting a new release

### Create a release branch for openshift/knative-client repo:

* Check that a remote reference to openshift and upstream exists
```bash
$ git remote -v | grep -e 'openshift\|upstream'
openshift	git@github.com:openshift/knative-client.git (fetch)
openshift	git@github.com:openshift/knative-client.git (push)
upstream	https://github.com/knative/client.git (fetch)
upstream	https://github.com/knative/client.git (push)
```

* Create a new release branch which points to upstream release branch + OpenShift specific files:
```bash
# Create a new release branch. Parameters are the upstream release tag
# and the name of the branch to create
# Usage: ./create-release-branch.sh <upstream-tag> <downstream-release-branch>
# <upstream-tag>: The tag referring the upstream release
# <downstream-release-branch>: Name of the release branch to create
$ ./create-release-branch.sh v0.14.0 release-v0.14.0

# Push release branch to openshift/knative-client repo
$ git push openshift release-v0.14.0
```

### Create a ci-operator configuration, prow job configurations and image mirroring config:

* Create a fork and clone of https://github.com/openshift/release
* Create a new ci-operator configuration:
```bash
# Jump into the knative client config directory in the openshift/release
$ cd ci-operator/config/openshift/knative-client

# Copy over the last release's config to a release specific config with
# the name of the yaml file ends with the new release branch name (e.g. release-v0.14.0)
$ cp openshift-knative-client-release-v0.13.0.yaml openshift-knative-client-release-v0.14.0.yaml

# Adapt the configuration for the kn new image name
# - Change .promotion.name to a release specific name (knative-v0.14.0)
# - Change .binary_build_commands to a release tag as below:
   TAG=v0.14.0 make install
   TAG=v0.14.0 make build-cross
$ vi openshift-knative-client-release-v0.14.0.yaml
```

* Create prow job configurations:
```bash
# Jump to top-level repo directory
$ cd ../../../../

# Call Prow job generator via Docker. You need a local Docker daemon installed
# This will generate necessary presubmit and postsubmit prow jobs config YAML files
$ docker run -it -v $(pwd)/ci-operator:/ci-operator:z  \
     registry.svc.ci.openshift.org/ci/ci-operator-prowgen:latest \
     --from-dir /ci-operator/config --to-dir /ci-operator/jobs
```

* Create image mirroring config:
```bash
# Add the image mirroring settings (create an empty file if not present)
$ vi core-services/image-mirroring/knative/mapping_knative_v0_14_quay

# Add following lines for the kn image like below
registry.svc.ci.openshift.org/openshift/knative-v0.14.0:kn quay.io/openshift-knative/kn:v0.14.0
registry.svc.ci.openshift.org/openshift/knative-v0.14.0:kn-cli-artifacts quay.io/openshift-knative/kn-cli-artifacts:v0.14.0
```

### Create a PR against openshift/release repo for CI setup of release branch using configs generated above:
```bash
# Verify the changes
$ git status
On branch master
Your branch is ahead of 'origin/master' by 180 commits.
  (use "git push" to publish your local commits)

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

	modified:   core-services/image-mirroring/knative/mapping_knative_v0_12_quay

Untracked files:
  (use "git add <file>..." to include in what will be committed)

	ci-operator/config/openshift/knative-client/openshift-knative-client-release-v0.14.0.yaml
	ci-operator/jobs/openshift/knative-client/openshift-knative-client-release-v0.14.0-postsubmits.yaml
	ci-operator/jobs/openshift/knative-client/openshift-knative-client-release-v0.14.0-presubmits.yaml

# Add & Commit all and push to your repo
$ git add .
$ git commit -a -m "knative-client release v0.14.0 setup"
$ git push

# Create pull request on https://github.com/openshift/release with your changes
# Once PR against openshift/release repo is merged, the CI is setup for release-branch
```

### Update Dockerfile in release branch with correct version:
```bash
# Update Dockerfile with current release number:
# - Change value of tag to current release (RUN TAG="v0.14.0" make build)
# - Change value of LABEL 'version' to current release (v0.14.0)
$ vi Dockerfile

# Verify the changes and raise a PR against release branch
$ git status
$ git add .
$ git commit -m "Update Dockerfile for release v0.14.0"
```
Note: After CI is setup for release branch, we'll need to raise at least one PR against
target release branch, have CI run and merge of PR, this ensures image gets mirrored at quay as postsubmit job.

* For further changes which are specific to OpenShift, raise PR against release branch.

### Once the changes to release branch is finalized, and we are ready for QA, create tag and push:
```bash
$ git tag openshift-v0.14.0
$ git push --tags
```

Note: Notify any changes required for this release, for e.g.: new commands, commands output update, etc. to docs team.
