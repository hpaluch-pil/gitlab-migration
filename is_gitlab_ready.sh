#!/bin/bash

# Check if GitLab is healthy/ready

set -e
set -o pipefail

BASE_URL=http://localhost

# required commands
for i in curl jq
do
	which $i > /dev/null || {
		echo "Please install command '$i'" >&2
		exit 1
	}
done

echo "Waiting for GitLab to be ready... - up to 180s"
for s in `seq 1 18`
do
	date
	if curl -fsS "$BASE_URL/-/readiness" | jq ;then
		break
	fi
	sleep 10
done
# try again to distinguish timeout from success
curl -fsS "$BASE_URL/-/readiness" >/dev/null  || {
	echo "Timeout - GitLab still not ready" >&2
	exit 1
}
echo
echo "OK: GitLab is ready"
exit 0
