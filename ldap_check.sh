#!/bin/bash
set -e
sd=''
[ `id -u` -eq 0 ] || sd="sudo"
set -x
cd /
$sd gitlab-rake gitlab:ldap:check
exit 0

