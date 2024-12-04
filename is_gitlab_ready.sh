#!/bin/bash

# Check if GitLab is healthy/ready

set -e
set -o pipefail

# BASE_URL below will work even for external_url with *https*, but you have to enable redirect
# in /etc/gitlab/gitlab.rb commenting out: nginx['redirect_http_to_https'] = true
# followed by: gitlab-ctl reconfigure
# It will still enable *http* health checks on 127.0.0.1:80 while redirecting anything else to https
BASE_URL=http://localhost

# required commands
for i in curl jq
do
	which $i > /dev/null || {
		echo "Please install command '$i'" >&2
		exit 1
	}
done

sd=''
[ `id -u` -eq 0 ] || sd="sudo "

log=`mktemp`
trap "rm -f -- $log" EXIT

gitlab_web_ready ()
{
	echo "Waiting for GitLab Web to be ready... - up to 300s"
	for s in `seq 1 30`
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
	echo -n "OK: "
	awk '{print "System Uptime (s): " $1}' /proc/uptime
}

gitlab_bg_migration_completed ()
{
	echo "Checking if Background migration is complete..."
	set -x
	$sd gitlab-psql -c 'select job_class_name, table_name, column_name, job_arguments from batched_background_migrations where status not in (3,6)' | tee $log
	set +x
	fgrep -q '(0 rows)' $log || {
		echo "Error - migration is not complete - must return (0 rows)" >&2
		exit 1
	}
	echo "OK"
}

gitlab_migration_completed ()
{
	echo "Checking if old Migration is finished..."
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
	echo "OK"
}

gitlab_prometheus_backends_up ()
{
	echo "Checking if all Prometheus backends are up..."
	curl -fSs 'http://localhost:9090/api/v1/query?query=up' |
	jq -r '{"metric": { "instance": "instance", "job" : "job" }, "value": ["x","value"]} , .data.result[] |
	       [.metric.instance, .metric.job, .value[1]] |
	       @csv' | tee $log
	fgrep -q '","1"' $log || {
		echo "Prometheus query returned no data" >&2
		exit 1
	}
	if fgrep -q '","0"' $log;then
		echo
		echo "ERROR: These Prometheus backends are DOWN:" >&2
		fgrep '","0"' $log
		exit 1
	fi
	echo "OK: all backends are up"
}

gitlab_web_ready

gitlab_prometheus_backends_up

gitlab_bg_migration_completed

gitlab_migration_completed

echo
echo "OK: GitLab is ready"
exit 0
