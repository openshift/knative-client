# This script is used to package kn cross platform cli artifacts
# for kn-cli-artifacts image
# Copyright 2020 The OpenShift Knative Authors
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

pkg_tar() {
  local dir
  case "$1" in
    x86_64)
		  dir=linux
    	mkdir "${OUTDIR}/${dir}"
      mv kn-linux-amd64 ${OUTDIR}/${dir}/kn
      chmod +x ${OUTDIR}/${dir}/kn
      ;;
    macos)
		  dir=macos
    	mkdir "${OUTDIR}/${dir}"
    	mv kn-darwin-amd64 ${OUTDIR}/${dir}/kn
      chmod +x ${OUTDIR}/${dir}/kn
      ;;
      #uncomment following when we support building mentioned archs
      #aarch64|ppc64le|s390x) dir=linux-${1};;
  esac
  cp LICENSE ${OUTDIR}/${dir}
  tar -zcf kn-${dir}-amd64.tar.gz -C ${OUTDIR}/${dir} .
}

pkg_zip_for_windows() {
  mkdir "${OUTDIR}/windows"
	mv kn-windows-amd64.exe ${OUTDIR}/windows/kn.exe
	cp LICENSE ${OUTDIR}/windows/
	zip --quiet --junk-path - ${OUTDIR}/windows/* > kn-windows-amd64.zip
}

OUTDIR=$(mktemp -dt knbinary.XXXXXXXXXX)
trap "rm -rf '${OUTDIR}'" EXIT INT TERM

pkg_tar x86_64
pkg_tar macos
pkg_zip_for_windows
