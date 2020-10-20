#!/bin/bash

# A standalone script to update `faas` as a plugin dependecies
# It can be combined with FAAS_REPO and FAAS_VERSION param 
# to overide default values.
#
# Usage: FAAS_REPO=value FAAS_VERSION=value update-faas.sh

ROOT_DIR=$(dirname "$0")/../..
source "$ROOT_DIR/openshift/release/common.sh"

update_faas_plugin
