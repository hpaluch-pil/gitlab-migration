#!/bin/bash
set -e
sd=''
[ `id -u` -eq 0 ] || sd="sudo"
set -x
cd /
$sd gitlab-ctl check-config
$sd gitlab-rake gitlab:check
$sd time gitlab-rake gitlab:git:fsck
$sd gitlab-rake gitlab:artifacts:check
$sd gitlab-rake gitlab:lfs:check
$sd gitlab-rake gitlab:uploads:check
$sd gitlab-rake gitlab:doctor:secrets
exit 0

