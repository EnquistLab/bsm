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

function jsonArrayToTable(){
	###############################
	# Output JSON as tab-delimited 
	# table with underlined header
	###############################
	jq '( .[0] | ([keys_unsorted[] | .] |(., map(length*"-"))) ), (.[] | [.[]]) | @csv'  | tr -d '\\'| column -t -s","  | tr -d '\"' 
} 

function ck_response() {
	########################################
	# Check or initialize service
	########################################
	
	# assume success
	status_mode=0

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
	req_json='{"opts":'$opts',"data":'$data'}'
	resp_json=$(curl -s -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: application/json" \
	  -H "charset: UTF-8" \
	  -d "$req_json" \
	  "$URL" \
	  )
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

# Set default overall status and route statuses to pass
status_overall=0;
status_resolve=0;
status_parse=0;

########################
# Test 1: Resolve mode
########################

if ! $quiet; then 
	echo "------------------------------------------------------------"
	echo -e "Test 1: Resolve mode\n"
fi

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

# Set options
# Which options are set and how can differ among API routes
MODE="resolve"
SOURCES="wcvp,usda"
CLASS="wfo"
MATCHES="best"

if ! $quiet; then \
	echo "Settings:"
	echo "  MODE=${MODE}"
	echo "  SOURCES=${SOURCES}"
	echo "  CLASS=${CLASS}"
	echo "  MATCHES=${MATCHES}"
fi

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  --arg sources "$SOURCES" \
  --arg class "$CLASS" \
  --arg matches "$MATCHES" \
  '{"mode": $mode, "sources": $sources, "class": $class, "matches": $matches}')
data=$(csvjson "${DATADIR}/ckapi_${svc}_data.csv")

# Send request to service
if ! $quiet; then echo -n "Sending request..."; fi
send_request
if ! $quiet; then echo "done"; fi
if ! $quiet && $verbose; then 
	echo "done"
	echo -e "Results:\n"
	echo "$resp_json" | jq 'map({Name_submitted, Name_matched})' | jsonArrayToTable
	echo " "
fi

# Set names of response and reference files
f_resp="ckapi_${svc}_resolve.json"
f_ref="${f_resp}.reference"

# Test or initialize service
# Save return value as service-specific status code
ck_response
status_resolve=$status_mode

########################
# Test 2: Parse mode
########################

if ! $quiet; then 
	echo "------------------------------------------------------------"
	echo -e "Test 2: Parse mode\n"
fi

# Only option used is $MODE
# $SOURCES and $CLASS are required but not used
# Need to fix this eventually
MODE="parse"

if ! $quiet; then \
	echo "Settings:"
	echo "  MODE=${MODE}"
fi

# Compose options & data JSON objects
opts=$(jq -n \
  --arg mode "$MODE" \
  --arg sources "$SOURCES" \
  --arg class "$CLASS" \
  '{"mode": $mode, "sources": $sources, "class": $class}')
data=$(csvjson "${DATADIR}/ckapi_${svc}_data.csv")

# Send request to service
if ! $quiet; then echo -n "Sending request..."; fi
send_request
if ! $quiet; then echo "done"; fi

# Echo response
if ! $quiet && $verbose; then 
	# Extract subset of element from JSON and echo as table with header
	echo -e "Results:\n"
	echo "$resp_json" | jq 'map({Name_submitted, Genus, Specific_epithet, Unmatched_terms})' | jsonArrayToTable
	echo " "
fi

# Set names of response and reference files
f_resp="ckapi_${svc}_parse.json"
f_ref="${f_resp}.reference"

# Test or initialize service
# Save return value as service-specific status code
ck_response
status_parse=$status_mode


