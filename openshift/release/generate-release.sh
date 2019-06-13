#!/usr/bin/env bash

#source $(dirname $0)/resolve.sh

release=$1
output_binary="kn"

if [ $release = "ci" ]; then
    output_binary="kn-ci"
    tag=""
else
    output_binary="kn"
    tag=$release
fi
