#!/bin/bash

##############################################################
# Check multiple services using up_svc.sh
##############################################################

##############################################################
# Usage:
# ./up_svc_batch.sh [-q] [-m [EMAIL_ADDRESSES]]
#
# Options:
#	-q: quiet
#	-m: send email notification of services with non-
#		zero exit status. Followed by optional parameter
#		EMAIL_ADDRESSES. Separate multiple addresses
#		with commas. If addresses not supplied 
# 		uses default parameter $email (see below). 
##############################################################

# Set working directory
DIR="$(cd "$(dirname "$0")" && pwd)"

######################################################
# Local parameters
# Only parameters in this file you may need to change
######################################################

# Error notification email subject
header="BIEN service error notification"

# Error notification email body title
ti="The following BIEN services may be down:"

######################################################
# External parameters
# Set in shared parameters file (params.sh)
######################################################

# Load default parameters
source ${DIR}/params.sh

# List of service URLs to check (from params file)
doms=$SVCS

# Default notification email(s)
# Overridden if email(s) supplied with -m option
email_default=$EMAIL_DEF

########################
# Functions
########################

function status_msg(){
	###############################
	# Returns status message for a
	# give integer status code
	#
	# Usage:
	# status_msg "$status"
	###############################

	case $status in
	  0)
		statusmsg="OK"
		;;
	  1)
		statusmsg="inaccessible"
		;;
	  2)
		statusmsg="timed out"
		;;
	  3)
		statusmsg="not found"
		;;
	  4)
		statusmsg="connection refused"
		;;
	  5)
		statusmsg="offline or bad url"
		;;
	  *)
		statusmsg="unknown error"
		;;
	esac	
	
	echo "$statusmsg"
}

########################
# Get options
########################

quiet=false
notify=false
url=""
email=""
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )		quiet=true
        					;;
		-m | --mailto )		notify=true
							shift
							email=$1
							;;
        * )                 echo "invalid option!"; exit 1
    esac
    shift
done	

if [ "$email" == "" ]; then
	email=$email_default
fi

# "quiet" option for up_svc command
q_opt=""
if $quiet; then q_opt="-q"; fi

########################
# Main
########################

if ! $quiet; then echo "Checking service status"; fi

domsdown=""
first_loop=1

# Remove leading and trailing newlines, if present
doms="${doms#$'\n'}"
doms="${doms%$'\n'}"

while IFS='' read dom; do
	IFS='|' read -ra arr <<< "$dom"
	svc="${arr[0]}"
	svc_disp="${svc} ${arr[1]}"
	url="${arr[2]}"
	
	# Strip trailing command from url, if present
	base_url="${url/:\/\//PROTOCOL_DELIM}"
	base_url="${base_url%/*}"
	base_url="${base_url/PROTOCOL_DELIM/:\/\/}"

	if ! $quiet; then 
		echo "${svc_disp}:"
		echo -n "  "
	fi
	
	# Check status of current service
	${DIR}/up_svc.sh $q_opt -u $base_url
	status=$?
	
 	if [ ! "$status" == "0" ]; then 
		# Compile status messages for services with errors
		status_msg=$(status_msg "$status")	
		domdown="${svc_disp} (${base_url}): ${status_msg} [exit status ${status}]" 	
		(( $first_loop )) 		&&  # "((...))" is bash specific
		domsdown="$domdown"    ||  # First -> Set
		domsdown="$domsdown\n$domdown"           # After -> Append
		unset first_loop
    fi
done <<< $doms

if $notify && [ "$domsdown" != "" ]; then
	# Send error message
	if ! $quiet; then echo -n "Sending sending service error notification..."; fi
	domsdown=$(echo -e "$domsdown")
	body=$(echo -e "${ti}\n\n${domsdown}")
	echo -e "${body}\n\n"`date` | mail -s "$header" $email; 
	if ! $quiet; then echo "done"; fi
fi

