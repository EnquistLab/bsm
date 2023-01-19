#!/bin/bash

##############################################################
# Check multiple services using up_svc.sh
##############################################################

##############################################################
# Usage:
# ./upsite_batch.sh [-q] [-m [EMAIL_ADDRESSES]]
#
# Options:
#	-q: quiet
#	-m: send email notification of services with non-
#		zero exit status. Followed by optional parameter
#		EMAIL_ADDRESSES. Separate multiple addresses
#		with commas. If addresses not supplied 
# 		uses default parameter $email (see below). 
##############################################################


######################################################
# Parameters
######################################################

# Set working directory
DIR="$(cd "$(dirname "$0")" && pwd)"
DATADIR="${DIR}/data"

# Load default parameters
source ${DIR}/params.sh

# List of service base URLs to check (from params file)
doms=$SVC_BASE_URLS

# Default notification email(s)
# Overridden is email(s) supplied with -m option
email_default=$EMAIL_DEF

#
# Other parameters
#

# Verbose by default
quiet=false

# Error notification email subject
header="BIEN service error notification"

# Error notification email body title
ti="The following BIEN services may be down:"

########################
# Get options
########################

url=""
email=""
notify=false
	
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

# "quiet" option for upsite command
q_opt=""
if $quiet; then q_opt="-q"; fi

########################
# Main
########################

if ! $quiet; then echo "Checking service status"; fi

DIR="$(cd "$(dirname "$0")" && pwd)"

domsdown=""
first_loop=1

for dom in $doms; do
	IFS='|' read -r -a arr <<< "$dom"
	svc=${arr[0]}
	svc_disp="${svc//_/ }"
	url="${arr[1]}"
	
	if ! $quiet; then 
		echo "${svc_disp}:"
		echo -n "  "
	fi
	
	# Check status of current service
	${DIR}/up_svc.sh $q_opt -u $url
	status=$?
	
	if [ ! "$status" == "0" ]; then 
	
		# Get full-text status message
		case $status in
		  1)
			statusmsg="- service up, with errors"
			;;
		  2)
			statusmsg="- service timed out, server OK"
			;;
		  3)
			statusmsg="- service down or bad url, server OK"
			;;
		  4)
			statusmsg="- server offline or unknown"
			;;
		  *)
			statusmsg=""
			;;
		esac	
	
		# Compile status messages for services with errors
		domdown="${svc_disp} (${url}): exit status ${status} ${statusmsg}" 	
		(( $first_loop )) 		&&  # "((...))" is bash specific
		domsdown="$domdown"    ||  # First -> Set
		domsdown="$domsdown\n$domdown"           # After -> Append
		unset first_loop
    fi
done	

# echo " "
# echo "Domains down:"
# echo -e "$domsdown"
# 
if $notify && [ "$domsdown" != "" ]; then
	# Send error message
	if ! $quiet; then echo -n "Sending sending service error notification..."; fi
	domsdown=$(echo -e "$domsdown")
	body=$(echo -e "${ti}\n\n${domsdown}")
	echo -e "${body}\n\n"`date` | mail -s "$header" $email; 
	if ! $quiet; then echo "done"; fi
fi

