##############################################################
# Check endpoint responses of multiple services
##############################################################

##############################################################
# Usage:
# ./ck_svc_batch.sh [-q] [-m [EMAIL_ADDRESSES]]
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

# List of services to check
# One service abbreviation per line
# Use lower case (e.g., tnrs), no quotes or commas
svcs="
tnrs
"

# Set working directory
DIR="$(cd "$(dirname "$0")" && pwd)"
DATADIR="${DIR}/data"

# Load default parameters
source ${DIR}/params.sh

# Default notification email(s)
# Overridden is email(s) supplied with -m option
email_default=$EMAIL_DEF

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

# "quiet" option for upsite command
q_opt=""
if $quiet; then q_opt="-q"; fi

########################
# Main
########################

if ! $quiet; then echo "Service endpoint checks"; fi

for svc in $svcs; do 
	svc_upper=${svc^^}
	f_svc_results="${DATADIR}/ck_${svc}_results.csv"
	
	if ! $quiet; then echo -n "Checking service \"${svc_upper}\"..."; fi
	
# 	# Delete previous results file if present
# 	rm_svc_results_cmd="rm ${DATADIR}/${f_svc_results}"
# 	eval "$ck_svc_cmd"

	# Check the service
	ck_svc_cmd="./ck_${svc}.sh ${q_opt}"
	eval "$ck_svc_cmd"
	
	row=1
	while IFS="," read -r svc mode status; 	do
	  echo "mode: ${mode}"
	  echo "status: ${status}"
	  echo ""
	  row=$(($row+1))
	done < <(tail -n +2 "${f_svc_results}")	
	
	# Get full-text status message
	case $status in
	  1)
		statusmsg="- FAIL: response changed"
		;;
	  2)
		statusmsg="- ERROR: no response"
		;;
	  *)
		statusmsg="- Unknown status code"
		;;
	esac	



done
