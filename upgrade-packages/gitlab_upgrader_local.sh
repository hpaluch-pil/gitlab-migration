#!/bin/bash

# incremental gitlab upgrader from local DEBs
# see: https://docs.gitlab.com/ee/update/index.html#upgrade-paths

set -e
set -o pipefail

sd=''
[ `id -u` -eq 0 ] || sd='sudo'

# required commands
for i in curl jq
do
	which $i > /dev/null || {
		echo "Please install command '$i'" >&2
		exit 1
	}
done

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

yellow="$(tput setaf 3)"
white="$(tput setaf 7)"

declare -A warnings
warnings[12.0.12-ce.0]="If your GitLab CE database contains leftovers
from EE edition - the database migration may cresh.
Plase see:
- https://gitlab.com/gitlab-org/gitlab-foss/-/issues/66277#note_205812949
for possible workaround"
warnings[13.12.10-ce.0]="GitLab 13.x now uses hashed path of git repositories.
After upgrade please use these commands:
- to check legacy projects: $sd gitlab-rake gitlab:storage:list_legacy_projects
- to migrate legacy projects: $sd gitlab-rake gitlab:storage:migrate_to_hashed
Also please remove legacy Service Templates after upgrade"

for i in  11.11.8-ce.0 \
        12.0.12-ce.0 12.1.17-ce.0 12.10.14-ce.0 \
	13.0.14-ce.0 13.1.11-ce.0 13.12.15-ce.0 \
	14.0.12-ce.0 14.9.4-ce.0
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
	deb=./gitlab-ce_${i}_amd64.deb
	[ -r "$deb" ] || {
		echo "Unable to read '$deb' file" >&2; exit 1
	}
	[ $wanted_fp_ver -ne 140007 ] || {
		echo "Checking for legacy (non-hashed) projects..."
		# all repositories MUST be hashed before install of 14.x
		legacy_count=$($sd gitlab-rake gitlab:storage:list_legacy_projects |
			head -1 | awk '/ Found/ {print $3}' )
		[[ $legacy_count =~ ^[0-9]+$ ]] || { echo "Invalid count of legacy projects '$legacy_count'" >&2; exit 1; }
		[ $legacy_count -eq 0 ] || {
			echo "Your GitLab Instllation still has $legacy_count legacy (non-hashed) projects"
			echo "You must migrate your repositories using this command:"
			echo "$sd gitlab-rake gitlab:storage:migrate_to_hashed"
			echo "Before upgrading to GitLab 14+"
			exit 1
		}
	}
	echo "Simulating Upgrade"
	# use this for install from repository:
	# $sd apt-get -s install "gitlab-ce=$wanted_ver"
	set -x
	$sd apt-get -s install "$deb"
	set +x
	echo "End of simulation"
	[ -z "${warnings[$i]}" ] || {
		echo "$yellow"
		echo "UPGRADE WARNING:"
		echo "${warnings[$i]}"
		echo "$white"
	}
	echo -n "Should really install $wanted_ver of gitlab-ce [y/N]? "
	read ans
	[ "x$ans" = "xy" ] || { echo "Aborting" >&2; exit 1; }
	# use this for install from repository:
	# $sd apt-get install "gitlab-ce=$wanted_ver"
	set -x
	$sd apt-get install "$deb"
	$sd apt-mark hold gitlab-ce || true
	set +x
	echo "Waiting for gitlab ce to be ready... - up to 180s"
	for s in `seq 1 18`
	do
		sleep 10
		date
		if curl -fsS "http://localhost/-/readiness" | jq ;then
			break
		fi
	done
	echo
	[ $wanted_fp_ver -lt 121014 ] || {
		jobs_count=9999
		while [ "x$jobs_count" != "x0" ]
		do
			[ "x$jobs_count" = "x9999" ] || {
				echo "There are $jobs_count background jobs - waiting 60s..."
				sleep 60
			}
			set -x
			jobs_count=$($sd  gitlab-rails runner -e production 'puts Gitlab::BackgroundMigration.remaining')
			set +x
			[[ $jobs_count =~ ^[0-9]+$ ]] || {
				echo "Unexpected job count '$jobs_count' - must be integer" >&2
				exit 1
			}
		done
	}
	echo
	echo "OK - gitlab seems to be ready - running checks..."
	set -x
	$sd gitlab-ctl check-config
	$sd gitlab-rake gitlab:check
	set +x
	echo "VERIFY MANUALLY THAT CHECKS ARE OK."
	echo -n "Type 'y' to proceed to next upgrade [y/N]? "
	read ans
	[ "x$ans" = "xy" ] || { echo "Aborting" >&2; exit 1; }
done

exit 0
