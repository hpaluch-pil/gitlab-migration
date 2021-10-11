#!/bin/bash

# Backups only SQL data on GitLab - ripped from preinst scripts

set -e
sd=''
[ `id -u` -eq 0 ] || sd='sudo '

set -x
$sd gitlab-rake gitlab:backup:create \
    SKIP=repositories,uploads,builds,artifacts,lfs,registry,pages
exit 0

