#!/bin/bash
# This script backs an instance up at scaleway (a nice virtual server hosting company)
# Check the latest source on https://github.com/MoonCactus/scaleway_remote_backup
# (c) Jeremie FRANCOIS - jeremie.francois@tecrd.com - https://www.linkedin.com/in/jeremiefrancois/
# This script is published under the GNU GENERAL PUBLIC LICENSE (see LICENSE)

set -e

usage()
{
cat << EOF
$(basename $0) - Remotely make backups of scaleway server instances.

Backs the provided scaleway instance up, with sequential names like "myserver-keyword-23".
When done, destroy the previous backups that specifically match the 'keyword'.

Usage:
EOF
	sed -n "s/^\s\+['\"]\([A-Za-z0-9-]\+\)['\"].*#O\s\(.\)/  \1 \2/p" "$0"
	cat << 'EOF'

Omit --token for the script to ask interactively (so your API token does not show up in the process list nor shell history)
Omit --server to display the list of your servers, by id and name
Omit --keyword to show the list of your backups for the server

You can use different keywords for different backup time scales, like 'daily' and 'weekly'.
E.g. use two interleaved two-week cronjobs named 'weekA' and 'weekB' to ensure a 1-2 week old backup at all times.

Notes:
- snapshots are not completely immediate.
- scaleway "bare metal" servers must be powered off before they can be backuped.

Exit states:
  0: success
  1: usage
  2: missing jq tool
  3: invalid API token
  4: server not found
  5: unstable server
  6: backup failed

EOF
	exit 1
}

if ! which jq >/dev/null; then
	echo 'This scripts requires "jq". Please install it on your system!'
	exit 2
fi

API_TOKEN=
SERVER_NAME=
KEYWORD=
SERVER_STATUS='n'
ZONE='nl-ams-1'

while [[ $# -gt 0 ]]; do
	o="$1"
	shift
	case "$o" in
	'--token')      #O <SCALEWAY_API_TOKEN: your private API key (see User Account / Credentials / API Tokens on Scaleway). It can also be a file that contains the token.
		API_TOKEN="$1"
		[[ -f "$API_TOKEN" ]] && API_TOKEN=$(grep '^[a-zA-Z0-9]' "$API_TOKEN")
		shift
		;;
	'--server')     #O <SERVER_NAME>: either the scaleway identifier or the exact name of the server to backup
		SERVER_NAME="$1"
		shift
		;;
	'--zone')     #O <ZONE_NAME>: nl-ams-1 or fr-par-1
		ZONE="$1"
		shift
		;;
	'--status')     #O dumps server status (JSON structure)
		SERVER_STATUS='y'
		;;
	'--keyword')    #O <KEYWORD>: (requires --server) a keyword to use within the name of the backup.
		KEYWORD="$1"
		shift
		;;
	*)
		usage
		;;
	esac
done

if [[ -z "$API_TOKEN" ]]; then
	echo -n "Enter your scaleway API token (like ffffffff-ffff-ffff-ffff-ffffffffffff): "
	read API_TOKEN
fi


APIURL="https://api.scaleway.com/instance/v1/zones/$ZONE"

# Beautifier on error (set -e)
trap 'date; echo' exit 

# Curl wrapper for calling scaleway API. See https://developers.scaleway.com/en/products/instance/api/
CALL()
{
	curl --silent --location --header "X-Auth-Token: $API_TOKEN" "$@" -H "Content-Type: application/json"
}

########################################################################

# Get organization from the API key. This also serves as a test.
ORGANIZATION=$(CALL https://account.scaleway.com/organizations -H "X-Auth-Token: $API_TOKEN" | jq .organizations[0].id | tr -d '"')
if [[ "$ORGANIZATION" = 'null' ]]; then
	echo "Your API auth key is probably invalid (found no matching organization). Check at scaleway."
	exit 3
fi

echo "Organization found: $ORGANIZATION"

# LIST SERVERS
serverlist=$(CALL --request GET "${APIURL}/servers" --data '' | jq '.servers[]|.id,.name' | paste -d, - -)

if [[ -z "$SERVER_NAME" ]]; then
	echo "Here are your servers. Provide an existing id or name with --server to make a backup:"
	echo "$serverlist" | sed 's/^/  /'
	exit
fi

# get id from id or from name (exact match is required)
SERVERID=$(echo "$serverlist" | grep "\"$SERVER_NAME\"" | cut -d, -f1 | tr -d '"')

if [[ -z "$SERVERID" ]]; then
	echo "Server '$SERVER_NAME' not found. Run without --server to get a list."
	exit 4
fi

########################################################################

# GET SERVER DETAILS
SERVERNAME=$(echo "$serverlist" | grep "\"$SERVERID\"" | cut -d, -f2 | tr -d '"')
srvjson=$(CALL --request GET "${APIURL}/servers/${SERVERID}" --data '')
SERVERID=$(echo "$srvjson" | jq .server.id | tr -d '"')
ROOTVOLUME=$(echo "$srvjson" | jq .server.image.root_volume.id)   # useful mostly when you want to create a new server
ARCHTYPE=$(echo "$srvjson" | jq .server.image.arch | tr -d '"')
SERVER_STATE=$(echo "$srvjson" | jq '.server.state' | tr -d '"')

# LIST EXISTING IMAGES
printf 'Server: "%s" (id:"%s", arch:"%s") has following existing images:\n' "$SERVERNAME" "$SERVERID" "$ARCHTYPE"

imagelist=$(CALL --request GET "${APIURL}/images?organization=${ORGANIZATION}" |
	jq '.images[]|.id,.name,.modification_date,.from_server' | paste - - - - |
	grep "\"$SERVERID\"$" | awk '{print $1 " " $3 " " $2}')

if  [[ -z "$imagelist" ]]; then
	echo "  (none)"
else
	echo -n "$imagelist" | sed 's/^/  /'
fi
echo

if [[ "$SERVER_STATUS" = 'y' ]]; then
	echo "Server status:"
	echo "$srvjson" | jq .
fi

if [[ -z "$KEYWORD" ]]; then
	echo "Done"
	trap '' exit 
	exit
fi

if [[ "$SERVER_STATE" = 'stopping' ]] ||  [[ "$SERVER_STATE" = 'starting' ]]; then
	echo "FAIL: cannot back server up as server is currently '$SERVER_STATE'"
	exit 5
fi

########################################################################

# COMPUTE THE AUTOBAK NAME AND SEQUENTIAL INDEX
maxidx=$(echo "$imagelist" | sed -n 's/.* ".*-'${KEYWORD}'-\([0-9]\+\)"$/\1/p' | sort -n | tail -1)  # max index
[[ -z "$maxidx" ]] && maxidx=0
maxidx=$(($maxidx + 1))
BAKNAME="${SERVERNAME}-${KEYWORD}-${maxidx}"

# CREATE IMAGE
printf 'Creating backup image: "%s"\n' "$BAKNAME"
# The following API call fails with a weird authentication issue:
#   payload=$(printf '{ "organization":"%s", "name":"%s", "arch":%s, "root_volume":%s }' "${ORGANIZATION}" "${BAKNAME}" "${ARCHTYPE}" "${ROOTVOLUME}")
# So we do it by mimicking the WEB UI call:
payload=$(printf '{"action":"backup","name":"%s"}' "$BAKNAME")
result=$(CALL "${APIURL}/servers/$SERVERID/action" --data "$payload")

if ! echo "$result" | grep -q '"status": "pending"'; then
	# The API may reply something like "message":"at least one volume attached to the server is not available"
	echo "FAIL: Your server or its volumes may be busy right now (server state is '$SERVER_STATE'). The API returned this error:"
	echo "$result" | jq .
	exit 6
fi

########################################################################

# DELETE FORMER AUTOBACKUPS
echo "$imagelist" | grep -- "-${KEYWORD}-" | grep -v -- "-${KEYWORD}-${maxidx}" | while read IMGID IMGDATE IMGNAME; do
	echo "Deleting previous backup image: $IMGNAME ($IMGDATE, $IMGID)"
	IMGID=$(echo "$IMGID" | tr -d '"')
	CALL "${APIURL}/images/${IMGID}" -X DELETE
done

# Then, delete the associated snapshot(s)
CALL --request GET "${APIURL}/snapshots" |
	jq '.snapshots[]|.id,.name' | paste - - |
	grep "\"${SERVERNAME}-${KEYWORD}-" | grep -v "\"$BAKNAME" |
	while read SNAPID SNAPNAME; do
		echo "  Deleting associated snapshot: $SNAPNAME ($SNAPID)"
		SNAPID=$(echo "$SNAPID" | tr -d '"')
		CALL "${APIURL}/snapshots/${SNAPID}" -X DELETE  
	done

########################################################################

echo "SUCCESS: backup successfully ordered, remote name is '$BAKNAME'"

# HOW TO CREATE A SERVER (UNUSED)
create_server()
{
	echo
	echo "Creating server"
	SRVNAME='testserver'
	SRVIMG='bd859e89-fb2d-466a-a546-383630a1ead1'   # eg. the docker image id to build the server upon (ex. Scaleway Ubuntu Xenial)
	SRVTYPE='ARM64-2GB'                             # this is also the "commercial name" (as shown on scaleway web interface)
	SRVTAGS='["apiserver"]'
	payload=$(printf '{"name": "%s", "image": "%s", "commercial_type": "%s", "tags":%s, "organization": "%s"}'  "$SRVNAME" "$SRVIMG" "$SRVTYPE" "$SRVTAGS" "$ORGANIZATION")
	CALL "${APIURL}/servers" -d "$payload"
}
