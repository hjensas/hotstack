#!/bin/bash

set -euxo pipefail

pushd /var/tmp

curl -sL https://github.com/openstack-k8s-operators/repo-setup/archive/refs/heads/main.tar.gz | tar -xz

pushd repo-setup-main

python3 -m venv ./venv
PBR_VERSION=0.0.0 ./venv/bin/pip install ./

# This is required for FIPS enabled until trunk.rdoproject.org
# is not being served from a centos7 host, tracked by
# https://issues.redhat.com/browse/RHOSZUUL-1517
update-crypto-policies --set FIPS:NO-ENFORCE-EMS

./venv/bin/repo-setup current-podified -b antelope

popd

rm -rf repo-setup-main
