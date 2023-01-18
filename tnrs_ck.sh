#!/bin/bash

#################################################
# Check TNRS API routes functioning as expected
#################################################

#################################################
# Status codes
#
# status_overall
# 0 All tests passed
# 1 One or more tests failed
#
# status_<route>
# 0 Pass
# 1 Fail, response content different from reference
# 2 Error, reference file not found
#################################################

########################
# Parameters
########################

# Set working directory & load default parameters
DIR="$(cd "$(dirname "$0")" && pwd)"
DATADIR="${DIR}/data"

source ${DIR}/params.sh

# Default URL from params file
URL_DEF=$URL_DEF_TNRS

# Service name for messages and filenames
# Use short code, lowercase, no spaces
svc="tnrs"
svc_upper=${svc^^}

########################
# Functions
########################

function unset_all(){
	###############################
	# Unset options and data 
	# Prevent accidental carry-over
	# from one test to another
	###############################

	unset MODE
	unset SOURCES
	unset CLASS
	unset MATCHES
	unset opts
	unset data	
}

function echo_start(){
	if ! $quiet; then 
		if $init; then
			action="Initializing"
		else
			action="Testing"
		fi
		
		echo "------------------------------------------------------------"
		echo -e "${action} mode ${MODE}\n"
	fi
}

function echo_opts(){
	if ! $quiet; then \
		#echo "Settings:"
		echo "MODE=${MODE}"
		if [ ! "$SOURCES" == "" ]; then echo "SOURCES=${SOURCES}"; fi
		if [ ! "$CLASS" == "" ]; then echo "CLASS=${CLASS}"; fi
		if [ ! "$MATCHES" == "" ]; then echo "MATCHES=${MATCHES}"; fi
	fi
}

function jsonArrayToTable(){
	###############################
	# Output JSON as tab-delimited 
	# table with underlined header
	###############################
	jq '( .[0] | ([keys_unsorted[] | .] |(., map(length*"-"))) ), (.[] | [.[]]) | @csv'  | tr -d '\\'| column -t -s","  | tr -d '\"' 
} 

function echo_resp(){
	###############################
	# Echo JSON response as table
	# $flds is comma-delimited list
	# of field to echo
	###############################

	if ! $quiet && $verbose; then 
		echo -e "Results:\n"
		#echo "$resp_json" | jq 'map({Name_submitted, Name_matched})' | jsonArrayToTable
		map_flds="map({"$flds"})"
		echo "$resp_json" | jq "$map_flds" | jsonArrayToTable
		echo " "
	fi
}

function ck_response() {
	########################################
	# Check or initialize service
	########################################
	
	# assume success
	status_mode=0

	# Set names of response and reference files
	f_resp="ckapi_${svc}_${MODE}.json"
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
				if ! $quiet; then echo -e "pass\n"; fi
			else
				if ! $quiet; then
					echo -e "FAIL: responses differ\n"
				fi
				status_overall=1
				status_mode=1
			fi
		fi
	fi
	
	#echo $status_mode
}

function send_request(){
	if ! $quiet; then echo -n "Sending request..."; fi
	resp_json=$(curl -s -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: application/json" \
	  -H "charset: UTF-8" \
	  -d "$req_json" \
	  "$URL" \
	  )
	if ! $quiet; then echo "done"; fi
}

function append_results(){
	cat << EOT >> ${DATADIR}/ckapi_${svc}_results.csv
${svc},${MODE},${status_mode}
EOT
}

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

if ! $quiet; then 
	if $init; then
		echo -e "Initializing TNRS service checks\n"
	else
		echo -e "Running TNRS service checks\n"
	fi
	
	echo "URL: ${URL}"
	echo "Notify: ${notify}"
	
	if $notify; then echo "Mail to: ${email}"; fi
	echo " ";
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
cat << EOT > ${DATADIR}/ckapi_${svc}_results.csv
svc,mode,status
EOT

########################
# Test resolve mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
MODE="resolve"
SOURCES="wcvp,usda"
CLASS="wfo"
MATCHES="best"
flds="Name_submitted,Name_matched"

echo_start
echo_opts

# Prepare test data
if ! $quiet; then echo -n "Preparing test data..."; fi 
cat << EOT > ${DATADIR}/ckapi_${svc}_data.csv
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
EOT
if ! $quiet; then echo "done"; fi

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  --arg sources "$SOURCES" \
  --arg class "$CLASS" \
  --arg matches "$MATCHES" \
  '{"mode": $mode, "sources": $sources, "class": $class, "matches": $matches}')
data=$(csvjson "${DATADIR}/ckapi_${svc}_data.csv")
req_json='{"opts":'$opts',"data":'$data'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test parse mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="parse"
flds="Name_submitted, Genus, Specific_epithet, Unmatched_terms"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
data=$(csvjson "${DATADIR}/ckapi_${svc}_data.csv")
req_json='{"opts":'$opts',"data":'$data'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test metadata mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="meta"
flds="db_version, build_date, code_version, api_version"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
req_json='{"opts":'$opts'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test sources mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="sources"
flds="sourceID, sourceName, version, tnrsDateAccessed"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
req_json='{"opts":'$opts'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test citations mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="citations"
flds="source"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
req_json='{"opts":'$opts'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test classifications mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="classifications"
flds="sourceID, sourceName"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
req_json='{"opts":'$opts'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results

########################
# Test collaborators mode
########################

# Parameters for this mode:
#   api options
#   flds - results fields to display (comma-delimited(
unset_all
MODE="collaborators"
flds="collaboratorName, collaboratorNameFull"

echo_start
echo_opts

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  '{"mode": $mode}')
req_json='{"opts":'$opts'}'

# Send request to service
send_request

# Echo response JSON as table
echo_resp

# Test or initialize service
# Save return value as service-specific status code
ck_response
append_results


