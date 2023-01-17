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

function jsonArrayToTableBAK(){
	###############################
	# Output JSON as tab-delimited 
	# table with header
	###############################
	jq '( .[0] | keys_unsorted ), (.[] | [.[]]) | @csv'  | tr -d '\\'| column -t -s","  | tr -d '\"' 
} 

########################
# Get options
########################

url=""
email=""
notify=false
quiet=false
init=false
	
while [ "$1" != "" ]; do
	# Get options		
	case $1 in
        -q | --quiet )		quiet=true
        					;;
        -i | --initialize )		init=true
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
 	if ! $quiet; then echo "Server parameter not defined, using default"; fi
	URL=$URL_DEF
fi

if [ "$email" == "" ]; then
 	if ! $quiet; then echo "Notification email parameter not defined, using default"; fi
	email=$EMAIL_DEF
fi


echo "email="$email

# "silent" option for curl command
s_opt=""
if $quiet; then s_opt="-s"; fi

########################
# Setup
########################

if ! $quiet; then 
	if $init; then
		echo "Initializing TNRS service checks"
	else
		echo "Running TNRS service checks"
	fi
	echo -e "URL="$URL"\n"
fi

# Set overall status and route statuses
status_overall=0;
status_resolve=0;
status_parse=0;

########################
# Prepare test data
########################

if ! $quiet; then echo "Preparing test data..."; fi 
cat << EOT > ${DATADIR}/ckapi_${svc}_data.csv
id,species
1,"Connarus venezuelanus"
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

########################
# Test 1: Resolve mode
########################

if ! $quiet; then 
	echo "------------------------------------------------------------"
	echo -e "Test 1: Resolve mode\n"
fi

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

if ! $quiet; then echo -n "Sending API request..."; fi
opts=$(jq -n \
  --arg mode "$MODE" \
  --arg sources "$SOURCES" \
  --arg class "$CLASS" \
  --arg matches "$MATCHES" \
  '{"mode": $mode, "sources": $sources, "class": $class, "matches": $matches}')
data=$(csvjson "${DATADIR}/ckapi_${svc}_data.csv")
req_json='{"opts":'$opts',"data":'$data'}'
resp_json=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "charset: UTF-8" \
  -d "$req_json" \
  "$URL" \
  )
if ! $quiet; then echo "done"; fi

if ! $quiet; then 
	# Extract elements from JSON and echo as table with header
	echo -e "Results:\n"
	echo "$resp_json" | jq 'map({Name_submitted, Name_matched})' | jsonArrayToTable
	echo " "
fi

# Set names of response and reference files
f_resp="ckapi_${svc}_resolve.json"
f_ref="ckapi_${svc}_resolve.json.reference"

if ! $quiet; then echo -n "Saving response JSON..."; fi
echo "$resp_json" > "${DATADIR}/${f_resp}"
if ! $quiet; then echo -e "done"; fi

if ! $quiet; then echo -n "Comparing response JSON to reference JSON..."; fi

if [ ! -f "${DATADIR}/$f_ref" ]; then
	if ! $quiet; then 
		echo "ERROR: Reference file not found"
		echo "[HINT: Run command with option '-i' first]"
	fi
	status_overall=1
	status_resolve=2
else
	diff "${DATADIR}/${f_resp}" "${DATADIR}/${f_ref}" &>/dev/null
	result=$?

	# Echo result and set status
	if [ "$result" == "0" ]; then
		if ! $quiet; then echo -e "pass\n"; fi
	else
		if ! $quiet; then
			echo -e "FAIL: response and reference differ\n"
		fi
		status_overall=1
		status_resolve=1
	fi
fi


echo "Exiting..."; exit 0





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
	echo "MODE=${MODE}"
	echo "Reusing previous input data"
fi

if ! $quiet; then echo -n "Sending API request..."; fi
opts=$(jq -n \
  --arg mode "$MODE" \
  --arg sources "$SOURCES" \
  --arg class "$CLASS" \
  '{"mode": $mode, "sources": $sources, "class": $class}')
data=$(csvjson ${DATADIR}"/"ckapi_tnrs_data.csv)
req_json='{"opts":'$opts',"data":'$data'}'
resp_json=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "charset: UTF-8" \
  -d "$req_json" \
  "$URL" \
  )
if ! $quiet; then echo -e "done\n"; fi

if ! $quiet; then 
	echo -e "Results:\n"
	echo "$resp_json" | jq 'map({Name_submitted, Genus, Specific_epithet, Unmatched_terms})' | jsonArrayToTable
	echo " "
fi

if ! $quiet; then echo -n "Saving response JSON..."; fi
echo "$resp_json" > ${DATADIR}"/"ckapi_tnrs_parse.json
if ! $quiet; then echo -e "done\n"; fi


echo "Exiting..."
exit 0


if ! $quiet; then echo -n "Comparing response JSON to reference JSON..."; fi
diff ${DATADIR}"/"ckapi_tnrs_parse.json ${DATADIR}"/"ckapi_tnrs_parse.json.reference #&>/dev/null
result=$?

# Exit with appropriate exit status
if [ "$result" == "0" ]; then
	if ! $quiet; then echo -e "pass\n"; fi
	exit 0
else
	if ! $quiet; then echo -e "FAIL\n"; fi
	status_overall=1
	status_parse=1
fi
	