##############################################################
# Check endpoint responses of multiple services
##############################################################

##############################################################
# Usage:
# ./ck_svc_batch.sh [-q] [-c] [-v] [-i] [-m [EMAIL_ADDRESSES]]
#
# Options:
#	-q: quiet
#	-c: curt mode. Only reports if one or more errors returned
#		by service. Does not echo output from ck_<service> script.
#	-v: verbose
#	-i: initialize
#	-m: send email notification of services if one or more
#		services report errors. If followed by optional 
#		parameter EMAIL_ADDRESSES, uses the latter instead of 
#		default	address(es) from params file. Separate multiple 
#		addresses with commas. 
##############################################################

######################################################
# Set directories load external parameters
######################################################

# Set working directory
DIR="$(cd "$(dirname "$0")" && pwd)"

# Load default parameters from separate
# parameters file
source ${DIR}/params.sh

# Default notification email(s), as supplied by
# parameters file. Overridden by emails supplied on
# command line if -m option followed by EMAIL_ADDRESSES
# parameter value
email_default=$EMAIL_DEF

# List of services to check
doms=$APIS

########################
# Get options
########################

quiet=false
curt=false
notify=false
init=false
url=""
email=""
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )		quiet=true
        					;;
        -c | --curt )		curt=true
        					;;
        -v | --verbose )	verbose=true
        					;;
        -i | --initialize )	init=true
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

# "quiet" option for ck_[SERVICE] commands
q_opt=""
if $quiet || $curt; then q_opt="-q"; fi

# "init" option for ck_[SERVICE] commands
i_opt=""
if $init; then i_opt="-i"; fi

# "mail" option for ck_[SERVICE] commands
m_opt=""
if $notify; then m_opt="-m ${email}"; fi

# Start by assuming no errors returned
noerrs=0

########################
# Main
########################

if ! $quiet; then echo -e "BIEN service endpoint checks\n"; fi

# Remove leading and trailing newlines, if present
doms="${doms#$'\n'}"
doms="${doms%$'\n'}"

# Check each service, as specified in shared parameters file
while IFS='' read dom; do
	status=0
	IFS='|' read -ra arr <<< "$dom"
	svc=${arr[0],,}
	inst="${arr[1]}"
	svc_upper="${arr[0]}"
	svc_disp="${svc_upper} ${inst}"
	url="${arr[2]}"
	
	# Make  no-whitespace, lowercase version of instance
	# for naming instance-specific results files
	inst_nw=${inst// /_}; inst_nw=${inst_nw,,}

	# API results file for this service
	f_svc_results="${DATADIR}/ck_${svc}_results.csv"	

# 	echo "svc: ${svc}"
# 	echo "svc_disp: ${svc_disp}"
# 	echo "url: ${url}"
	
	if ! $quiet; then 
		echo "#####################################################"
		echo "Checking service \"${svc_disp}\":"
	fi

	# Check the service
	case $svc in
	  tnrs)
		./ck_tnrs.sh ${q_opt} ${m_opt} ${i_opt} -s "$inst_nw" -u "$url"
		status=$?
		if ! $quiet; then echo "done"; fi
		;;
	  gnrs)
		./ck_gnrs.sh ${q_opt} ${m_opt} -u $url
		status=$?
		if ! $quiet; then echo "done"; fi
		;;
	  nsr)
		#./ck_nsr.sh ${q_opt} ${m_opt} -u $url
		#status=$?
		if ! $quiet; then echo "UNDER CONSTRUCTION"; fi
		;;
	  gvs)
		#./ck_gvs.sh ${q_opt} ${m_opt} -u $url
		#status=$?
		if ! $quiet; then echo "UNDER CONSTRUCTION"; fi
		;;
	  *)
		echo "Unknown service"; exit 1
		;;
	esac	
	
	if ! $quiet; then
		if [ "$status" == "2" ]; then
			echo -e "WARNING: one or more modes returned error (non-zero exit status)\n"
			noerrs=2
		else
			echo " "
		fi
	fi

# 	row=1
# 	while IFS="," read -r svc mode status; 	do
# 	  echo "mode: ${mode}"
# 	  echo "status: ${status}"
# 	  echo ""
# 	  row=$(($row+1))
# 	done < <(tail -n +2 "${f_svc_results}")	


done <<< $doms

# Echo final status on exit
exit $noerrs
