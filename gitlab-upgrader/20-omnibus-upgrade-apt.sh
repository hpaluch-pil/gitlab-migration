#!/bin/bash
# 20-omnibus-upgrade-apt.sh - upgrade just GitLab package (Omnibus) - for APT distributions
# should be done only after ./10-os-updates-apt.sh
set -euo pipefail

# expected distribution class (ID_LIKE in /etc/os-release)
EXP_ID_LIKE=debian
OS_STATE_DIR=$HOME/.config/gitlab-upgrader/10-os-updates-apt
STATE_DIR=$HOME/.config/gitlab-upgrader/$(basename -s .sh "$0")
# Timestamp - must be unique per day
TS="$(date '+%F')"

# prints "debian" for Debian and Ubuntu
print_id_like ()
{
	source /etc/os-release && echo "$ID_LIKE"
}

verbose_command ()
{
	echo "Running '$@'..."
	"$@"
}

# optional: override next GitLab Version (specify "18.0.*" to install "18.0.x")
GL_NEXT_VERSION="${GL_NEXT_VERSION:-}"

# verify that 10-os-updates-apt.sh finished OS updates:
fos=$OS_STATE_DIR/$TS-20-finished
[ -f "$fos" ] || {
	echo "ERROR: You have to run ./10-os-updates-apt.sh first" >&2
	exit 1
}

# ff=finished file
ff="$STATE_DIR/$TS-99-finished"
[ ! -f "$ff" ] || {
	echo "ERROR: Upgrade is already finished for today - state file '$ff' already exists." >&2
	exit 1
}

cd "$(dirname $0)"
echo "INFO: User=`id -un`, UID=`id -u`"

[ `id -u` -ne 0 ] || {
	echo "ERROR: This script may NOT be run as root (it uses sudo internally)" >&2
	exit 1
}

# NOTE: We do NOT check for "apt" command because openSUSE LEAP has sometime defined
# such aliases for its zypper package manager - confusing this script.
os_class="$(print_id_like)"
echo "INFO: OS class is: '$os_class'"
[ "$os_class" == "$EXP_ID_LIKE" ] || {
	echo "ERROR: got OS class '$os_class' but expected: '$EXP_ID_LIKE'" >&2
	exit 1
}

[ -d "$STATE_DIR" ] || verbose_command mkdir -p "$STATE_DIR"

gl_ver="$(dpkg -l gitlab-ce | awk ' $2 == "gitlab-ce" { print $3 }')"
echo "INFO: installed gitlab-ce version: '$gl_ver'"
# valid version string: 17.8.7-ce.0
[[ $gl_ver =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-ce\.0$ ]] || {
	echo "ERROR: GitLab version '$gl_ver' has unexpected format" >&2
	exit 1
}
gl_major=${BASH_REMATCH[1]}
gl_minor=${BASH_REMATCH[2]}
gl_patch=${BASH_REMATCH[3]}
echo "INFO: GitLab version triplet: '$gl_major', '$gl_minor', '$gl_patch'"
gl_ver_normalized=$(( gl_major * 10000 + gl_minor * 100 + gl_patch ))
echo "INFO: GitLab normalized version: '$gl_ver_normalized'"

# n=next gitlab version in apt form : 17.8.'*'
gln=$gl_major.$(( gl_minor + 1 )).'*'
# allow override via environment variable
[ -z "$GL_NEXT_VERSION" ] || gln="$GL_NEXT_VERSION"
echo "INFO: Next GitLab version: '$gln'"
[[ $gln =~ ^([0-9]+)\.([0-9]+)\.\*$ ]] || {
	echo "GitLab next ver; '$gln' has unexpected format (should be like 17.8.*" >&2
	exit 1
}
ver_arg="gitlab-ce=$gln"

svc=gitlab-runsvdir.service
# GitLab must be in running state
gl_state="$(systemctl show -p SubState --value $svc)"
echo "Checking if $svc is running (state: $gl_state)"
[ "$gl_state" = running ] || {
	echo "ERROR: $svc is in state '$gl_state', expected 'running'" >&2
	exit 1
}

verbose_command	../is_gitlab_ready.sh

verbose_command apt-get install -s "$ver_arg"
echo -n "Are you sure to upgrade gitlab-ce package [y/N]? "
read ans
case "$ans" in 
	[yY]|[yY][eE][sS])
		verbose_command sudo apt-get install "$ver_arg"
		;;
	*)
		echo "ABORTED on user request"
		exit 1
		;;
esac
# immediately lock gitlab-ce package again to prevent upgrades by mistake...
verbose_command sudo apt-mark hold gitlab-ce

# CPU usage must be below 20% otherwise gitlab-ce is starting up (should not be interrupted):
echo "Waiting for CPU user% < 20% (gitlab-ce must be down or NOT starting)..."
while true
do
	cpu_usage=$(vmstat 1 2 | tail -1 | awk '{ print $(NF-4) }')
	[[ $cpu_usage =~ ^[0-9]+$ ]] || {
		echo "ERROR: CPU usage ($cpu_usage) must be number" >&2
		exit 1
	}
	echo "$(date '+%T') CPU user: $cpu_usage% (must be < %20)"
	[ $cpu_usage -gt 19 ] || break
	sleep 5
done

# mark that GitLab package upgrade is completed
verbose_command touch "$ff"

echo "OK: now poll ../is_gitlab_ready.sh script for finishing migrations"
exit 0
