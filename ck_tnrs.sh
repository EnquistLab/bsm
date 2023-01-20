#!/bin/bash

#################################################
# Check TNRS API routes functioning as expected
#################################################

##############################################################
# Usage:
# ./ck_tnrs.sh [-i] [-q] [-v] [-u [URL]] [-m [EMAIL_ADDRESSES]]
#
# Options:
#	-i: initialize, saving each response as reference JSON file
#	-q: quiet mode, no echo
#	-v: verbose mode. Ignored if -q also used
#	-u: service URL. If omitted or if optional URL parameter 
#		omitted, uses default $URL_DEF (see below). 
#	-m: send email notification of services with non-
#		zero exit status. Followed by optional parameter
#		EMAIL_ADDRESSES. Separate multiple addresses
#		with commas. If addresses not supplied 
# 		uses default parameter $email (see below). 
##############################################################

######################################################
# IMPORTANT NOTE
# In addition to the parameters below, the following
# functions will require editing to adapt this script 
# to other services:
# set_mode_params()
# unset_all()
# ck_svc()
######################################################

##############################################
# Parameters
#################################################

# Get working directory & set data directory
DIR="$(cd "$(dirname "$0")" && pwd)"

# Service name for messages and filenames
# Short code, lowercase, no spaces!
# E.g. "tnrs" not "TNRS"
svc="tnrs"

# List of API modes (endpoints) to test for this service
# One mode per line
# No commas or other delimiters
modes="
resolve
parse
meta
sources
classifications
citations
collaborators
"

# Test data
# Saved to CSV file
# Comma-delimited with header
read -d '' testdata <<"BLOCK"
id,species
2,"Connarus venezuelensis"
3,"Croton antisyphiliticus"
4,"Croton antisiphyllitius"
5,"Connarus sp.1"
6,"Connarus"
7,"Connaraceae Connarus absurdus"
8,"Connarus absurdus"
9,"Connaraceae Badgenus badspecies"
10,"Rosaceae Badgenus badspecies"
BLOCK

# Upper case version of service code
svc_upper=${svc^^}

# Error notification email subject
header="${svc_upper} error notification"

# Error notification email body title
ti="The following ${svc_upper} API modes returned errors:"


########################
# Internal parameters
# (do not change)
########################

# Load external params file to set remaining parameters
source ${DIR}/params.sh

# Default URL from params file
URL_DEF=$URL_DEF_TNRS

# Default notification email(s)
# Overridden is email(s) supplied with -m option
email_default=$EMAIL_DEF

# These need to be false to start
settings=false
prep_data=false

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
		statusmsg="- OK"
		;;
	  1)
		statusmsg="- FAIL: unexpected API response"
		;;
	  2)
		statusmsg="- ERROR: no response"
		;;
	  *)
		statusmsg="- Unknown error"
		;;
	esac	
	
	echo "$statusmsg"
}

function unset_all(){
	###############################
	# Unset opt and data JSON elements,
	# plus opt parameters other than $MODE
	# Prevents carry-over from one
	# test to another
	###############################

	unset SOURCES
	unset CLASS
	unset MATCHES
	unset opts
	unset data	
}

function echo_done(){
	if ! $quiet; then echo "done"; fi
}

function inlist() {
	###############################
	# IF string (arg1) is in list
	# (arg2), return true, else false.
	# Delimiter is arg3
	#
	# Usage:
	# inlist "pear" "apple,pear,orange" ","
	###############################
    value=$1
    list=$2
    delim=$3
    echo $list | tr "$delim" '\n' | grep -F -q -x "$value"
}

function echo_start(){
	if ! $quiet; then 
	
		if $prep_data; then
			msg="Preparing test data"
			prep_data=false
		elif $settings; then
			msg="Settings"
			settings=false
		else	
			if $init; then
				action="Initializing"
			else
				action="Testing"
			fi
			msg="${action} mode ${MODE}"
		fi

		echo "------------------------------------------------------------"
		echo -e "${msg}:"
	fi
}

function jsonArrayToTable(){
	###############################
	# Output JSON as tab-delimited 
	# table with underlined header
	###############################
	jq '( .[0] | ([keys_unsorted[] | .] |(., map(length*"-"))) ), (.[] | [.[]]) | @csv'  | tr -d '\\'| column -t -s","  | tr -d '\"' 
} 

function set_mode_params(){
	####################################
	# Set API request parameters for 
	# current MODE
	####################################
	
	if [ "$MODE" == "resolve" ]; then
		SOURCES="wcvp,usda"
		CLASS="wfo"
		MATCHES="best"
		flds="Name_submitted,Name_matched"
	elif [ "$MODE" == "parse" ]; then
		flds="Name_submitted, Genus, Specific_epithet, Unmatched_terms"
	elif [ "$MODE" == "meta" ]; then
		flds="db_version, build_date, code_version, api_version"
	elif [ "$MODE" == "sources" ]; then
		flds="sourceID, sourceName, version, tnrsDateAccessed"	
	elif [ "$MODE" == "classifications" ]; then
		flds="sourceID, sourceName"
	elif [ "$MODE" == "citations" ]; then
		flds="source"
	elif [ "$MODE" == "collaborators" ]; then
		flds="collaboratorName, collaboratorNameFull"
	else
		if ! $quiet; then echo "ERROR: unknown MODE \"${MODE}\"!"; fi
		exit 1
	fi	
}

function ck_response() {
	########################################
	# Check or initialize service
	########################################
	
	# assume success
	status_mode=0

	# Set names of response and reference files
	f_resp="ck_${svc}_${MODE}.json"
	f_ref="${f_resp}.reference"

	if $init; then
		if ! $quiet; then echo -n "Saving response JSON as reference file..."; fi
		echo "$resp_json" > "${DATADIR}/${f_ref}"
		if ! $quiet; then echo -e "done"; fi
	else
		if ! $quiet; then echo -n "Comparing current and reference responses..."; fi

		# Save response to file
		echo "$resp_json" > "${DATADIR}/${f_resp}"

		# Compare response and reference JSON files
		if [ ! -f "${DATADIR}/$f_ref" ]; then
			if ! $quiet; then 
				echo "ERROR: Reference file not found"
				echo "[HINT: Run command with option '-i' first]"
			fi
			status_overall=1
			status_mode=2
		else
			diff "${DATADIR}/${f_resp}" "${DATADIR}/${f_ref}" &>/dev/null
			result=$?

			# Echo result and set status
			if [ "$result" == "0" ]; then
				if ! $quiet; then echo -e "pass"; fi
			else
				if ! $quiet; then
					echo -e "FAIL: responses differ"
				fi
				status_overall=1
				status_mode=1
			fi
		fi
	fi
	
	#echo $status_mode
}

function ck_svc(){
	echo_start
	
	# Echo options
	if ! $quiet; then \
		#echo "Settings:"
		echo "MODE=${MODE}"
		if [ ! "$SOURCES" == "" ]; then echo "SOURCES=${SOURCES}"; fi
		if [ ! "$CLASS" == "" ]; then echo "CLASS=${CLASS}"; fi
		if [ ! "$MATCHES" == "" ]; then echo "MATCHES=${MATCHES}"; fi
	fi

	# Compose options JSON
	if [ "$MODE" == "resolve" ]; then
		opts=$(jq -n \
		  --arg mode "$MODE" \
		  --arg sources "$SOURCES" \
		  --arg class "$CLASS" \
		  --arg matches "$MATCHES" \
		  '{"mode": $mode, "sources": $sources, "class": $class, "matches": $matches}')
	else
		opts=$(jq -n --arg mode "$MODE" '{"mode": $mode}')
	fi
	
	if inlist "$MODE" "resolve,parse" ","; then
		# Include options + data in api request 
		data=$(csvjson "${DATADIR}/${f_testdata}")
		req_json='{"opts":'$opts',"data":'$data'}'
	else
		# Include options only 
		req_json='{"opts":'$opts'}'
	fi

	# Send request to service
	if ! $quiet; then echo -n "Sending request..."; fi
	resp_json=$(curl -s -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: application/json" \
	  -H "charset: UTF-8" \
	  -d "$req_json" \
	  "$URL" \
	  )
	echo_done

	# Echo response JSON as table
	# $flds is comma-delimited list of field to echo
	if ! $quiet && $verbose; then 
		echo -e "Results:\n"
		#echo "$resp_json" | jq 'map({Name_submitted, Name_matched})' | jsonArrayToTable
		map_flds="map({"$flds"})"
		echo "$resp_json" | jq "$map_flds" | jsonArrayToTable
		echo " "
	fi

	# Test or initialize service
	# Save return value as service-specific status code
	ck_response

	# Append current results to results file
	# Do not change indentation! Last two lines
	# must be flush with left margin.
	cat << EOT >> ${DATADIR}/ck_${svc}_results.csv
${svc},${MODE},${status_mode}
EOT
}

#################################################
# Main
#################################################

########################
# Get options
########################

url=""
email=""
notify=false
quiet=false
verbose=false
init=false
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )		quiet=true
        					;;
        -v | --verbose )	verbose=true
        					;;
        -i | --init )		init=true
        					;;
		-u | --url )		shift
							URL=$1
							;;
		-m | --mailto )		notify=true
							shift
							email=$1
							;;
        * )                 echo "invalid option!"; exit 1
    esac
    shift
done	

if [ "$URL" == "" ]; then
	URL=$URL_DEF
fi

if [ "$email" == "" ]; then
	email=$EMAIL_DEF
fi

# "silent" option for curl command
s_opt=""
if $quiet; then s_opt="-s"; fi

########################
# Setup
########################
unset_all

if ! $quiet; then 
	if $init; then
		echo -e "Initializing ${svc_upper} service checks\n"
	else
		echo -e "Running ${svc_upper} service checks\n"
	fi
	
	echo "Settings:"
	echo "URL: ${URL}"
	echo "Notify: ${notify}"
	if $notify; then echo "Mail to: ${email}"; fi
fi

# Set all statuses to pass
status_overall=0
status_resolve=0
status_parse=0
status_meta=0
status_sources=0
status_citations=0
status_classifications=0
status_collaborators=0

# Start results file (header)
cat << EOT > ${DATADIR}/ck_${svc}_results.csv
svc,mode,status
EOT

########################
# Prepare test data
########################

f_testdata="ck_${svc}_data.csv"
prep_data=true; echo_start

if ! $quiet; then echo -n "Saving test data to file \"${f_testdata}\"..."; fi 
echo "$testdata" > ${DATADIR}/${f_testdata}
echo_done

###############################
# Check service endpoints
###############################

for curr_mode in $modes; do
	unset_all
	MODE=$curr_mode
	set_mode_params
	ck_svc
done

###############################
# Send notification if errors
###############################

if [ ! "$status_overall" == "0" ]; then
	modes_err=""
	first_loop=1

	# Read results file & compile error messages
	while IFS="," read -r svc mode status; 	do

		if [ ! "$status" == "0" ]; then 
			status_msg=$(status_msg "$status")
			mode_err="${mode}: exit status ${status} ${statusmsg}" 	
			(( $first_loop )) 		&& 
			modes_err="$mode_err"    ||  
			modes_err="$modes_err\n$mode_err"    
			unset first_loop
		fi
	done < <(tail -n +2 "${DATADIR}/ck_${svc}_results.csv")	

	# Send notification email
	if $notify && [ "$modes_err" != "" ] && ! $init; then
		if ! $quiet; then echo -n "Sending sending service error notification..."; fi
		modes_err=$(echo -e "$modes_err")
		body=$(echo -e "${ti}\n\n${modes_err}\n\nURL: ${URL}\n\n")
		echo -e "${body}\n\n"`date` | mail -s "$header" $email; 
		if ! $quiet; then echo "done"; fi
	fi
fi
