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

# Dockerfile to bootstrap build and test in openshift-ci
FROM registry.svc.ci.openshift.org/openshift/release:golang-1.14

# Add kubernetes repository
ADD openshift/ci-operator/build-image/kubernetes.repo /etc/yum.repos.d/

RUN yum install -y kubectl ansible httpd-tools

RUN GO111MODULE=on go get github.com/mikefarah/yq/v3

# Allow runtime users to add entries to /etc/passwd
RUN chmod g+rw /etc/passwd
