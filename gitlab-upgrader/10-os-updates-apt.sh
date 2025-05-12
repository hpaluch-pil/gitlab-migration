#!/bin/bash
# 10-os-updates-apt.sh - operating system upgrades on GitLab machine - Ubuntu/Debian - APT
set -euo pipefail

# expected distribution class (ID_LIKE in /etc/os-release)
EXP_ID_LIKE=debian
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

# ff=finished file
ff="$STATE_DIR/$TS-20-finished"
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

f="$STATE_DIR/$TS-10-apt-update"
[ -f "$f" ] || {
	verbose_command sudo apt-get update
	verbose_command touch "$f"
}

# always ensure that gitlab-ce is locked
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

# if GitLab is running we have to stop it
gl_state="$(systemctl show -p SubState --value gitlab-runsvdir.service)"
echo "Checking if gitlab-ce is running (state: $gl_state)"
if [ "$gl_state" = running ]; then
	../is_gitlab_ready.sh
fi

if [ "$gl_state" = running ]; then
	# stop it if it is running
	verbose_command sudo systemctl stop gitlab-runsvdir.service
fi

# now we are allowed to upgrade OS packages
f="$STATE_DIR/$TS-12-apt-dist-upgrade"
[ -f "$f" ] || {
	verbose_command sudo apt-get dist-upgrade
	verbose_command touch "$f"
}

# also remove orphaned packages (typically obsoleted kernels)
f="$STATE_DIR/$TS-14-apt-autoremove"
[ -f "$f" ] || {
	verbose_command sudo apt-get autoremove --purge
	verbose_command touch "$f"
}

# mark that OS updates are completed
verbose_command touch "$ff"
echo "FINISHED (gitlab-ce is down): you should now reboot system with: sudo reboot"
exit 0
