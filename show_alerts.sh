#!/bin/bash

set -euo pipefail
#set -x
j=`mktemp`
trap "rm -f -- $j" EXIT
curl -fsS -o $j http://localhost:9090/api/v1/alerts
[ -s "$j" ] || {
	echo "Alert manager API returned no data" >&2
	exit 1
}
jq < $j
# status must be success
status=$(jq -r '.status' < $j)
[ "$status" = "success" ] || {
	echo "Unexpected status of Alert Manager: '$status'" >&2
	exit 1
}
# number of alerts
alerts=$(jq '.data.alerts | length' < $j)
echo "There are $alerts active alerts"
[[ $alerts =~ ^[0-9]+$ ]] || {
	echo "Alert parsing error: '$alerts' is not number" >&2
	exit 1
}
[[ $alerts = "0" ]] || {
	echo "ERROR: $alerts active alerts present"'!' >&2
	exit  1
}
echo "OK: no active alerts"

exit 0

