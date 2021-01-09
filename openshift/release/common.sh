#!/bin/bash
# Collection of shared functions used to generate and prepare releases.

ROOT_DIR=$(dirname $0)/../..

readonly FAAS_VERSION=${FAAS_VERSION:-"main"}
readonly FAAS_REPO=${FAAS_REPO:-"github.com/boson-project/faas"}

# The vendor/ dir is omitted to be added separately
UPDATED_FILES=$(cat <<EOT | tr '\n' ' '
pkg/kn/root/plugin_register.go
go.mod
go.sum
EOT
)

# Generates plugin_register.go file to enable plugin inlining
generate_file() {
  echo ":: Generating plugin_register.go file ::"
  local faas_repo=$1

  cp ${ROOT_DIR}/openshift/release/plugin_register.go ${ROOT_DIR}/pkg/kn/root/plugin_register.go

  # Add new import after placeholder comment containing #plugin#.
  # The `sed` append can be repeated for additional plugins.
  sed -i "/#plugins#/a _ \"${faas_repo}/plugin\"" ${ROOT_DIR}/pkg/kn/root/plugin_register.go

  # Format the file accordingly
  gofmt -w -s ${ROOT_DIR}/pkg/kn/root/plugin_register.go
}

# Generates replacements needed for faas.
# Review & adjust accordingly for every release.
mod_replace() {
  echo ":: Applying go.mod replacements ::"
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

# Updates and pulls go dependencies, same as upstreams hack/build.sh::update.
mod_update() {
  echo ":: Updating go dependencies ::"
  go mod tidy
  go mod vendor

  # Cleanup
  find "./vendor" \( -name "OWNERS" -o -name "*_test.go" \) -print0 | xargs -0 rm -f
}

# Creates new git commits with all the necessary files
add_files() {
  echo ":: Adding faas as a plugin ${FAAS_VERSION}::"
  local updated_files=$1
  pushd ${ROOT_DIR}
  git add ${updated_files}
  git commit -m ":space_invader: Add faas as a plugin ${FAAS_VERSION}"
  # Create distinct commit for vendor/ dir
  git add vendor
  git commit -m ":open_file_folder: Update vendor dir for faas ${FAAS_VERSION}"

  popd
}

# Wrapper to execute necessary steps to update faas dependencies.
update_faas_plugin() {
  generate_file "${FAAS_REPO}"
  mod_replace "${FAAS_VERSION}"
  mod_update
  add_files "${UPDATED_FILES}"
}
