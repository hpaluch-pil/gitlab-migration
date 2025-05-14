#!/bin/bash
# 10-os-updates-zypper.sh - operating system upgrades on GitLab machine - (open)SUSE - Zypper
# NOTE: If you are using proxy wrapper script you can use this command:
# $ PROXY_WRAPPER=proxy_command.sh ./10-os-updates-zypper.sh
set -euo pipefail

# expected distribution class (ID_LIKE in /etc/os-release)
EXP_ID_LIKE="suse opensuse" # yes, there are two words...
STATE_DIR=$HOME/.config/gitlab-upgrader/$(basename -s .sh "$0")
# Timestamp YYYY-MM-DD - must be unique per day
TS="$(date '+%F')"

# prints "debian" for Debian and Ubuntu, "suse opensuse" for openSUSE LEAP 15.6
print_id_like ()
{
	source /etc/os-release && echo "$ID_LIKE"
}

verbose_command ()
{
	echo "Running '$@'..."
	"$@"
}

wait_cpu_down ()
{
	local max_cpu=20
	# CPU usage must be below $max_cpu otherwise gitlab-ce is starting up (should not be interrupted):
	echo "Waiting for CPU user% < $max_cpu% (gitlab-ce must be down or NOT starting)..."
	while true
	do
		cpu_usage=$(vmstat 1 2 | tail -1 | awk '{ print $(NF-4) }')
		[[ $cpu_usage =~ ^[0-9]+$ ]] || {
			echo "ERROR: CPU usage ($cpu_usage) must be number" >&2
			exit 1
		}
		echo "$(date '+%T') CPU user: $cpu_usage% (must be < $max_cpu%)"
		[ $cpu_usage -ge $max_cpu ] || break
		verbose_command sleep 5
	done
}


# optional command to wrap proxy access, using ${var:-} to avoid undefined variable error (set -u)
PROXY_WRAPPER="${PROXY_WRAPPER:-}"

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

# NOTE: We do NOT check for "zypper" command because sometimes other distros
# install "foreign" packager (for example SUSE may install apt wrapper) - so we check for OS type
os_class="$(print_id_like)"
echo "INFO: OS class is: '$os_class'"
[ "$os_class" == "$EXP_ID_LIKE" ] || {
	echo "ERROR: got OS class '$os_class' but expected: '$EXP_ID_LIKE'" >&2
	exit 1
}

[ -d "$STATE_DIR" ] || verbose_command mkdir -p "$STATE_DIR"

f="$STATE_DIR/$TS-10-zypper-update"
[ -f "$f" ] || {
	verbose_command sudo $PROXY_WRAPPER zypper ref
	verbose_command touch "$f"
}

# always ensure that gitlab-ce is locked
verbose_command sudo zypper al gitlab-ce

# CPU usage must be below 20% otherwise gitlab-ce is starting up (should not be interrupted):
wait_cpu_down

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
f="$STATE_DIR/$TS-12-zypper-upgrade"
[ -f "$f" ] || {
	verbose_command sudo $PROXY_WRAPPER zypper up
	verbose_command touch "$f"
}

# mark that OS updates are completed
verbose_command touch "$ff"
echo
echo "FINISHED (gitlab-ce is down): you should now reboot system with: sudo reboot"
echo
exit 0
