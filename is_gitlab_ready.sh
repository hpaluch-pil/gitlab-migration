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
sd=''
[ `id -u` -eq 0 ] || sd="sudo "

echo "Checking if migration is complete..."
log=`mktemp`
trap "rm -f -- $log" EXIT
set -x
$sd gitlab-psql -c 'select job_class_name, table_name, column_name, job_arguments from batched_background_migrations where status <> 3' | tee $log
set +x
fgrep -q '(0 rows)' $log || {
	echo "Error - migration is not complete - must return (0 rows)" >&2
	exit 1
}
jobs_count=999
while [ $jobs_count -gt 0 ]
do
        date
        set -x
        jobs_count=$($sd  gitlab-rails runner -e production 'puts Gitlab::BackgroundMigration.remaining')
        set +x
        [[ $jobs_count =~ ^[0-9]+$ ]] || {
                echo "Unexpected job count '$jobs_count' - must be integer" >&2
                exit 1
        }
        echo "INFO: There are remaining $jobs_count jobs"
        [ $jobs_count -eq 0 ] || sleep 60
done
echo
echo "OK: GitLab is ready"
exit 0
