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

function resolve_resources(){
  local dir=$1
  local resolved_file_name=$2
  local image_prefix=$3
  local image_tag=$4

  [[ -n $image_tag ]] && image_tag=":$image_tag"

  echo "Writing resolved yaml to $resolved_file_name"

  > $resolved_file_name

  for yaml in "$dir"/*.yaml; do
    echo "---" >> $resolved_file_name
    # 1. Prefix test image references with test-
    # 2. Rewrite image references
    # 3. Update config map entry
    # 4. Remove comment lines
    # 5. Remove empty lines
    sed -e "s+\(.* image: \)\(github.com\)\(.*/\)\(test/\)\(.*\)+\1\2 \3\4test-\5+g" \
        -e "s+\(.* image: \)\(github.com\)\(.*/\)\(.*\)+\1 ${image_prefix}\4${image_tag}+g" \
        -e "s+\(.* queueSidecarImage: \)\(github.com\)\(.*/\)\(.*\)+\1 ${image_prefix}\4${image_tag}+g" \
        -e '/^[ \t]*#/d' \
        -e '/^[ \t]*$/d' \
        "$yaml" >> $resolved_file_name
  done
}
