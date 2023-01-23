#!/bin/bash



#
# Note: All working except statelist and countylist
# continue at statelist (coded but still not working)
#




#################################################
# Check GNRS API routes functioning as expected
#################################################

##############################################################
# Usage:
# ./ck_gnrs.sh [-i] [-q] [-v] [-d] [-u [URL]] [-s INSTANCE] [-m [EMAIL_ADDRESSES]] 
#
# Options:
#	-i: "init mode". Initialize checks, saving each response JSON
#		as a reference file. Be careful with this command; whatever 
#		is saved in init mode becomes the "correct" response when
# 		this script is run in normal (non-init) mode. To avoid saving
# 		error responses as reference, first run in normal mode with 
#		verbose option (-v) and visually inspect each response to 
#		make sure it is correct. 
#	-q: quiet mode, no echo
#	-v: verbose mode. Ignored if -q also used. In addition to normal
#		progress and error messages, displays API input and output,
# 		including raw JSON response and response formatted as a table
#		for easier inspection. Use this mode to visually confirm that 
#		all responses are as expected, before running in "init mode'.
#	-d: debug mode, extra verbose. Dumps everything verbose dumps, 
#		and more. Echoes the entire, raw API response.
#	-s: service instance. Short name for this instance.
# 		Follow format in params.sh., e.g., "GNRS production API". 
#		If omitted uses default $INST_GNRS_DEF (see below). 
#	-u: service URL. If omitted or if URL parameter 
#		omitted, uses default $INST_DEF_GNRS (see below). 
#	-m: send email notification of services with non-
#		zero exit status. Followed by optional parameter
#		EMAIL_ADDRESSES. Separate multiple addresses
#		with commas. If addresses not supplied 
# 		uses default parameter $EMAIL_DEF (see below). 
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
# E.g. "gnrs" not "GNRS"
svc="gnrs"

# List of API modes (endpoints) to test for this service
# One mode per line
# No commas or other delimiters
modes="
resolve
countrylist
statelist
countylist
dd
meta
sources
citations
collaborators
"
	
# Upper case version of service code
svc_upper=${svc^^}

# Error notification email subject
header="${svc_upper} error notification"

# Error notification email body title
ti="The following ${svc_upper} API modes returned errors:"

########################
# Internal parameters
########################

# Test data for mode "resolve"
# Saved to CSV file
# Comma-delimited with header
read -d '' testdata <<"BLOCK"
id,country,state_province,county_parish
user_id,country,state_province,county_parish
1,Canada,British Colombia,
2,Mexico,Chiapas,Municipio de Vila Corzo
3,Ukraine,Kharkiv,Novovodolaz'kyi
4,USA,Arizona,Pima County
5,USA,Puerto Rico,Mayaguez
6,Puerto Rico,Mayagüez,
7,UK,Scotland,Aberdeenshire
8,Scotland,Aberdeenshire,
BLOCK

# Test data for mode "statelist"
# Saved to CSV file
# Comma-delimited list of GNRS country IDs, with header
# Countries are: 'Costa Rica', 'Nicaragua', 'Panama'
read -d '' testdata_sl <<"BLOCK"
country_id
3624060
3703430
3617476
BLOCK

# Test data for mode "countylist"
# Saved to CSV file
# Comma-delimited list of GNRS state/province IDs, with header
read -d '' testdata_cl <<"BLOCK"
state_province_id
3624953
3624368
3830308
3620673
BLOCK


########################
# Internal parameters
# (do not change)
########################

# Load external params file to set remaining parameters
source ${DIR}/params.sh

# Default URL from params file
URL_DEF=$URL_DEF_GNRS

# Default URL from params file
INST_DEF=$INST_DEF_GNRS

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

# 	unset SOURCES
# 	unset CLASS
# 	unset MATCHES
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
 		BATCHES=2
# 		CLASS="wfo"
# 		MATCHES="best" 
		flds="poldiv_full, country, state_province, county_parish"
	elif [ "$MODE" == "countrylist" ]; then
		flds="country_id, country, iso_alpha3, continent"
	elif [ "$MODE" == "statelist" ]; then
		flds="state_province_id, country_id, country, state_province"
	elif [ "$MODE" == "countylist" ]; then
		flds="county_parish_id, country, state_province_ascii, county_parish"
	elif [ "$MODE" == "dd" ]; then
		flds="col_name, description"
	elif [ "$MODE" == "meta" ]; then
		flds="db_version, db_version_build_date, code_version, code_version_release_date"
	elif [ "$MODE" == "sources" ]; then
		flds="source_id, source_name, version, date_accessed"	
	elif [ "$MODE" == "citations" ]; then
		flds="source"
	elif [ "$MODE" == "collaborators" ]; then
		flds="collaborator_name, collaborator_name_full"
# 	else
# 		if ! $quiet; then echo "ERROR: unknown MODE \"${MODE}\"!"; fi
# 		exit 1
	fi	
}

function ck_response() {
	########################################
	# Check or initialize service
	########################################
	
	# assume success
	status_mode=0

	# Set names of response and reference files
	f_resp="ck_${svc}_${inst}_${MODE}.json"
	f_ref="${f_resp}.ref"

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
				echo "ERROR: Reference file \"${f_resp}\" not found"
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
	
	if ! $quiet; then echo " "; fi
	#echo $status_mode
}

function ck_svc(){
	echo_start
	
	# Echo options
	if ! $quiet; then 
		#echo "Settings:"
		echo "MODE=${MODE}"
#		if [ ! "$CLASS" == "" ]; then echo "CLASS=${CLASS}"; fi
	fi

	# Compose options JSON
	if [ "$MODE" == "resolve" ]; then
		opts=$(jq -n \
		  --arg mode "$MODE" \
		  --arg batches "$BATCHES" \
		  '{"mode": $mode, "batches": $batches}')
	else
		opts=$(jq -n --arg mode "$MODE" '{"mode": $mode}')
	fi
#	opts=$(jq -n --arg mode "$MODE" '{"mode": $mode}')
	
	if [ "$MODE" == "resolve" ] || [ "$MODE" == "statelist" ]  || [ "$MODE" == "countylist" ]; then
		# Include options + data in api request 
		if [ "$MODE" == "resolve" ]; then
			data_raw="${DATADIR}/${f_testdata}"
		elif [ "$MODE" == "statelist" ]; then
			data_raw="${DATADIR}/${f_testdata_sl}"		
		elif [ "$MODE" == "countylist" ]; then
			data_raw="${DATADIR}/${f_testdata_cl}"		
		fi
		
		data=$(csvjson "${data_raw}")

		if ! $quiet && ( $verbose || $debug ); then 
			echo -e "Input data:\n"
			data_flds=`head -n 1 ${data_raw}`
 			map_flds="map({"$data_flds"})"
			echo "$data" | jq "$map_flds" | jsonArrayToTable
			echo " "
		fi

		req_json='{"opts":'$opts',"data":'$data'}'
	else
		# Include options only 
		req_json='{"opts":'$opts'}'
	fi

	# Send request to service
	if ! $quiet; then echo -n "Sending request..."; fi
	#resp_full=$(curl -i -s -X POST \
	resp_full=$(curl -i -s -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: application/json" \
	  -H "charset: UTF-8" \
	  -d "$req_json" \
	  "$URL" \
	  )
	echo_done	
	
	# Extract http status and JSON data from response
	savenext=false		
	is_http_status=false
	http_status=""
	http_status_code=""
	
	while IFS='\n' read currline; do
		if echo "$currline" | grep -q "^HTTP/1.1"; then
 			# Save HTTP status line
 			http_status="$(echo ${currline}  | sed -E 's/HTTP\/1\.1 //g')"
			is_http_status=false; savenext=false
		elif [[ ! "$currline" =~ [^[:space:]] ]]; then
			# Blank line; save next line (=$resp_json)
			savenext=true
		elif $savecurr; then
			# Save JSON response
			resp_json="$currline"
			savenext=false
		fi
	done <<< $resp_full
	
	# Get status code
	# Requires IFS=" ", therefore must do after above loop
	if [ ! "$http_status" == "" ]; then
		read -ra arr <<<"$http_status"
		http_status_code="${arr[0]}"
	fi

	# Echo HTTP code
	if ! $quiet && ( $verbose || $debug ); then 
		echo -e "HTTP status: $http_status\n"
	fi
	
	# Echo raw response
	if ! $quiet && $debug ; then 
		echo -e "Full, raw response:\n"
		echo "$resp_full"
		echo " "
	fi

	# Echo response JSON
	if ! $quiet && $debug; then 
		echo -e "Response JSON:\n"
		echo "$resp_json"
		echo " "
	fi
	
	# Echo response JSON as table
	# $flds is comma-delimited list of field to echo
	if ! $quiet && ( $verbose || $debug ); then 
		echo -e "Response JSON as table:\n"

		if [ "$http_status_code" == "200" ]; then
			if [ "$flds" == "" ]; then
				# List all fields
				echo "$resp_json" | jsonArrayToTable
			else
				# List selected fields
				map_flds="map({"$flds"})"
				echo "$resp_json" | jq "$map_flds" | jsonArrayToTable
			fi
			
			echo " "
		fi
	fi

	# Test or initialize service
	# Save return value as service-specific status code
	ck_response

	# Append current results to results file
	# Do not change indentation! Last two lines
	# must be flush with left margin.
	cat << EOT >> ${DATADIR}/${f_results}
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
inst=""
email=""
notify=false
quiet=false
verbose=false
debug=false
init=false
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )		quiet=true
        					;;
        -v | --verbose )	verbose=true
        					;;
        -d | --debug )		debug=true
        					;;
        -i | --init )		init=true
        					;;
		-s | --instance )	shift
							inst=$1
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

# Use default instance if none supplied
if [ "$inst" == "" ]; then
	inst=$INST_DEF
fi

# Make instance string lower case with no whitespaces
if [ ! "$inst" == "" ]; then
	inst=${inst// /_}
	inst=${inst,,}
fi

# Use default URL if none supplied
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
	echo "Instance: ${inst}"
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
f_results="ck_${svc}_${inst}_results.csv"
cat << EOT > ${DATADIR}/${f_results}
svc,mode,status
EOT

########################
# Prepare test data
########################

prep_data=true; echo_start

# Data for mode='resolve'
f_testdata="ck_${svc}_data.csv"
if ! $quiet; then echo -n "Saving test data to file \"${f_testdata}\"..."; fi 
echo "$testdata" > ${DATADIR}/${f_testdata}

# Data for mode='statelist'
f_testdata_sl="ck_${svc}_data_statelist.csv"
if ! $quiet; then echo -n "Saving test data for mode 'statelist' to file \"${f_testdata_sl}\"..."; fi 
echo "$testdata_sl" > ${DATADIR}/${f_testdata_sl}

# Data for mode='statelist'
f_testdata_cl="ck_${svc}_data_countylist.csv"
if ! $quiet; then echo -n "Saving test data for mode 'countylist' to file \"${f_testdata_cl}\"..."; fi 
echo "$testdata_cl" > ${DATADIR}/${f_testdata_cl}

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

if [ "$status_overall" == "1" ]; then
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
	done < <(tail -n +2 "${DATADIR}/${f_results}")	

	if ! $quiet; then 
		echo "Overall status: FAIL, one or more errors reported"
	fi

	# Send notification email
	if $notify && [ "$modes_err" != "" ] && ! $init; then
		if ! $quiet; then 
			echo -n "Sending sending service error notification..."
		fi
		modes_err=$(echo -e "$modes_err")
		body=$(echo -e "${ti}\n\n${modes_err}\n\nURL: ${URL}\n\n")
		echo -e "${body}\n\n"`date` | mail -s "$header" $email; 
		if ! $quiet; then echo "done"; fi
	fi
	exit 1
elif [ "$status_overall" == "0" ]; then
	if ! $quiet; then 
		echo "------------------------------------------------------------"
		echo "Overall status: OK, no errors reported"
	fi 
	exit 0
else 
	if ! $quiet; then 
		echo "------------------------------------------------------------"
		echo "Error: unknown value of $overall_status"
	fi 
	exit 2
fi
