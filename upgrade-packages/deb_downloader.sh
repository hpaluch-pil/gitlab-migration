#!/bin/bash

# incremental gitlab upgrader
# see: https://docs.gitlab.com/ee/update/index.html#upgrade-paths

set -e
set -o pipefail
set -x

for i in  11.11.8-ce.0 \
        12.0.12-ce.0 12.1.17-ce.0 12.10.14-ce.0 \
	13.0.14-ce.0 13.1.11-ce.0 13.12.10-ce.0 \
	14.0.7-ce.0 14.1.3-ce.0
do
        #pool/bionic/main/g/gitlab-ce/gitlab-ce_10.7.0-ce.0_amd64.deb
	deb=gitlab-ce_${i}_amd64.deb
	if [ -r $deb ]; then
		echo "Package $deb already exists - skipping download..."
		continue
	fi
	curl -Lf -o $deb.tmp \
		https://packages.gitlab.com/gitlab/gitlab-ce/packages/ubuntu/bionic/$deb/download.deb
	mv $deb.tmp $deb
done
	md5sum -c packages.md5
exit 0
