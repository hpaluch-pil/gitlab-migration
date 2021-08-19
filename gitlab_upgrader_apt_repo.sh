#!/bin/bash

# incremental gitlab upgrader
# see: https://docs.gitlab.com/ee/update/index.html#upgrade-paths

set -e
set -o pipefail

sd=''
[ `id -u` -eq 0 ] || sd='sudo'

# return factored version from gitlab version string
function get_factored_version 
{
	set -e
	[ -n "$1" ] || { echo "Missing argument 1" >&2 ; exit 1 ; }
	gitlab_ver="$1"
	[[ $gitlab_ver =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-ce\.0$ ]] || { 
		echo "ERROR: Unable to parse version '$gitlab_ver'\n" >&2
		exit 1
	}
	declare -a versions
	versions=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]})
	# validate that no version is higher than 99 (would overflow FP format)
	for x in ${versions[@]}
	do
		[[ $x =~ ^[0-9]+$ ]] || { echo "Unable to parse '$x' as number" >&2 ; exit 1; }
		[ $x -lt 100 ] || { echo "Version number '$x' > 99" >&2 ; exit 1; }
	done
	(( fp_ver = ${versions[0]} * 10000 + ${versions[1]} * 100 + ${versions[2]} ))
	echo "$gitlab_ver $fp_ver"
}
# get version of installed gitlab
function get_installed_ver
{
	set -e
	# example: Version: 12.10.14-ce.0
	gitlab_ver=$(dpkg -s gitlab-ce | egrep '^Version:' | awk '{print $2}')
	get_factored_version "$gitlab_ver"
}
for i in  11.11.8-ce.0 \
        12.0.12-ce.0 12.1.17-ce.0 12.10.14-ce.0 \
	13.0.14-ce.0 13.1.11-ce.0 13.12.10-ce.0 \
	14.0.7-ce.0 14.1.3-ce.0
do
	# avoid runing 'read' in subshell (thus losing variables)
	shopt -s lastpipe
	get_factored_version $i | read wanted_ver wanted_fp_ver
	get_installed_ver | read inst_ver inst_fp_ver
	shopt -u lastpipe
	#echo "Installed version ($inst_ver $inst_fp_ver) => wanted ($wanted_ver $wanted_fp_ver)"
	[ $wanted_fp_ver -gt $inst_fp_ver ] || {
		echo "Installed version ($inst_ver $inst_fp_ver) is >= ($wanted_ver $wanted_fp_ver) - skipping"
		continue
	}
	echo "Simulating Upgrade"
	set -x
	$sd apt-get -s install "gitlab-ce=$wanted_ver"
	set +x
	echo "End of simulation"
	echo -n "Should really install $wanted_ver of gitlab-ce [y/N]? "
	read ans
	[ "x$ans" = "xy" ] || { echo "Aborting" >2; exit 1; }
	set -x
	$sd apt-get install "gitlab-ce=$wanted_ver"
	$sd apt-mark hold gitlab-ce || true
	set +x
	echo "Waiting for gitlab ce to be ready... - up to 180s"
	for s in `seq 1 18`
	do
		sleep 10
		date
		if curl -fsS "http://localhost/-/readiness" ;then
			break
		fi
	done
	echo
	echo "OK - gitlab seems to be ready..."
	echo -n "Please verify that gitlab is really running and continue with checks [y/N]? "
	read ans
	[ "x$ans" = "xy" ] || { echo "Aborting" >2; exit 1; }
	set -x
	$sd gitlab-ctl check-config
	$sd gitlab-rake gitlab:check
	[ $wanted_fp_ver -lt 130000 ] || $sd  gitlab-rails runner -e production 'puts Gitlab::BackgroundMigration.remaining'
	set +x
	echo "Checks finished - enumerating higher version"
done

exit 0
