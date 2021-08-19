#!/bin/bash

set -xe
sd=''
[ `id -u` -eq 0 ] || sd="sudo"
cd /
$sd gitlab-ctl check-config
$sd gitlab-rake gitlab:check
echo "skipping (too long):" $sd gitlab-rake gitlab:git:fsck
exit 0

