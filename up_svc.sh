#!/bin/bash

#################################################
# Check if base service is up and accepting requests
#################################################

# Exit status codes:
# 0: service up, status OK
# 1: service up, with errors
# 2: service timed out, server OK
# 3: service down or bad url, server OK
# 4: server down or bad server name

#################
# Parameters
#################

quiet=false
verbose=false

########################
# Get options
########################

url=""
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )			quiet=true
        						;;
        -v | --verbose )		quiet=false
        						verbose=true
        						;;
		-u | --url )			shift
								url=$1
								;;
        * )                     echo "invalid option!"; exit 1
    esac
    shift
done	

if [ "$url" == "" ]; then
	if ! $quiet; then echo "ERROR: server parameter not defined"; fi
	exit 5
fi

########################
# Extract server name
########################

server=$url
server=${server#"http://"}
server=${server#"https://"}
server=${server#"www."}
IFS=':' read -r -a arr <<< "$server"
server=${arr[0]}
IFS='/' read -r -a arr <<< "$server"
server=${arr[0]}

########################
# Check service status
# (port open on base url)
########################

if ! $quiet; then 
	echo -n "Checking service: $url..."; 
fi

# Note the following wget options:
# --spider: return 0 if resource found but do not download
# --server-response: Print HTTP headers and FTP responses
# Also: 2>&1: include error messages in STDOUT
response="$(wget --spider --server-response --timeout=5 --tries=1 $url 2>&1)"

if [ $(echo "$response" | grep -q "timed out"; echo $?) == 0 ]; then
	svc_status="timeout"
elif [ $(echo "$response" | grep -q "200 OK"; echo $?) == 0 ]; then
	svc_status="OK"
elif [ $(echo "$response" | grep -q "Name or service not known"; echo $?) == 0 ]; then
	svc_status="not found"
elif [ $(echo "$response" | grep -q "onnection refused"; echo $?) == 0 ]; then
	svc_status="Connection refused"
fi

if [[ $svc_status == "OK" ]] ; then
    if ! $quiet; then echo "OK ✓"; fi
	if $verbose; then echo "exit status = 0"; fi
    exit 0
elif [[ $svc_status == "timeout" ]] ; then
    if ! $quiet; then echo "timeout ✗"; fi
    exitcode=2
elif [[ $svc_status == "not found" ]] ; then
    if ! $quiet; then echo "not found ✗"; fi
    exitcode=3
elif [[ $svc_status == "Connection refused" ]] ; then
    if ! $quiet; then echo "Connection refused ✗"; fi
    exitcode=3
else
    if ! $quiet; then echo "service inaccessible ✗"; fi
    exitcode=1
fi

########################
# Check server status
########################

if ! $quiet; then 
	echo -n "  Checking server: $server..."
fi

# Server down or not responding
# nmap works even if IMCP/ping disabled 
nmap -PN -T4 -p 80 $server 2>&1 | grep -q "Host is up" 
# grep exit status=1 if host is down or bad server name
status=$( echo $? )
if [[ $status == 0 ]] ; then
	if ! $quiet; then echo "online ✓"; fi
else
	if ! $quiet; then echo "offline or bad url ✗"; fi
	exitcode=4
fi

if $verbose; then echo "exit status = "$exitcode; fi
exit $exitcode
