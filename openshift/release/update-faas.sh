#!/bin/bash


readonly ROOT_DIR=$(dirname $0)/../..

FAAS_VERSION=${1:-"main"}
FAAS_REPO="github.com/boson-project/faas"

UPDATED_FILES=$(cat <<EOT | tr '\n' ' '
vendor
pkg/kn/root/plugin_register.go
go.mod
go.sum
EOT
)


generate_file() {
  local faas_repo=$1
  
  cat <<EOF > "${ROOT_DIR}/pkg/kn/root/plugin_register.go"
// Copyright © 2020 The Knative Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package root

import (
	_ "${faas_repo}/plugin"
)

// RegisterInlinePlugins is an empty function which however forces the
// compiler to run all init() methods of the registered imports
func RegisterInlinePlugins() {}
EOF
}

mod_replace() {
  local faas_version=$1
  
  cat <<EOF >> "${ROOT_DIR}/go.mod"
replace (
    github.com/boson-project/faas => github.com/boson-project/faas ${faas_version}

    // Pin conflicting dependency versions
    // Buildpacks required version
    github.com/docker/docker => github.com/docker/docker v1.4.2-0.20200221181110-62bd5a33f707
    // Darwin cross-build required version
    golang.org/x/sys => golang.org/x/sys v0.0.0-20200302150141-5c8b2ff67527
)
EOF
}

mod_update() {
  go mod tidy
  go mod vendor
}

add_files() {
  local updated_files=$1
  pushd ${ROOT_DIR}
  
  git add ${updated_files}
  git commit -m ":open_file_folder: Add faas as a plugin."
}


generate_file "${FAAS_REPO}"

mod_replace "${FAAS_VERSION}"

mod_update

add_files "${UPDATED_FILES}"

