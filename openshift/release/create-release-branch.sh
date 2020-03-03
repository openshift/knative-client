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

# Usage: create-release-branch.sh v0.4.1 release-0.4

release=$1
target=$2

# Custom files
custom_files=$(cat <<EOT | tr '\n' ' '
openshift
OWNERS_ALIASES
OWNERS
Makefile
Dockerfile.rhel
Dockerfile.cliartifacts.rhel
package_cliartifacts.sh
container.yaml
content_sets.yaml
EOT
)


# Fetch the latest tags and checkout a new branch from the wanted tag.
git fetch upstream --tags
git checkout -b "$target" "$release"

# Update openshift's master and take all needed files from there.
git fetch openshift master
git checkout openshift/master $custom_files
git add $custom_files
git commit -m "Add openshift specific files."
