# BIEN Web Services Monitoring 

## Contents

- [Overview](#overview)
- [Software and dependencies](#dependencies)
- [The scripts](#scripts)
- [Automation using cron](#automation)

<a name="overview"></a>
## Overview

These scripts monitor accessibility, function and performance of APIs, R packages and web user interfaces to BIEN web services such as the TNRS, GNRS, and NSR. The scripts monitor two classes of attributes: (1) availability (is the service online?) and (2) function (are the main API endpoints and R package functions returning the expected responses?). All applications are designed to run unsupervised as cron jobs. See section [Automation using cron](#automation) for recommended cron configurations. Any individual command can also be run separately, with options for normal and verbose output. If the notification option is used, failure of one or more checks will trigger notifications emails to addresses specified in the shared parameter file. 

<a name="dependencies"></a>
## Software and dependencies

All scripts run on Linux-type systems. As some code is Bash-specific, we do not recommend running these applications in other shells unless you are prepared to do some refactoring.

Software/OS | Version
--- | ---
Ubuntu | 16.04 or higher  
Bash | 5.0.17
curl | 7.68.0
jq | 1.6

<a name="scripts"></a>
## The scripts

Script name | Type    | Purpose
----------- | ------- | -------
params.sh | Shared parameters file | Parameters used by all files. Not in GitHub. See publicly accessible example file `params.sh.example`
params.sh.example | Example shared parameters file | Template/example for `params.sh`
up\_svc.sh | Availability | Check the base URL of a service to confirm that it is up and accepting requests. If the service is down, checks the server as well. Returns exit codes 0 (success) or >1 (failure). See script for meaning of failuer codes.
 up\_svc\_batch.sh | Availability | Runs up\_svc.sh for multiple services and sends notification emails if errors detected
ck\_tnrs.sh | Performance | Tests each endpoint of TNRS API to confirm response content as expected. Save test results as CSV file, with a success/failure code and message for each test. See script for details of test results array. If enabled, sends notification email(s) if one or more errors detected.
ck\_svc\_batch.sh| Performance |  Runs performance check scripts (e.g., ck\_tnrs.sh, ck\_gnrs.sh, etc.) for multiple services. **[UNDER DEVELOPMENT]**
gnrs_ck.sh | Performance | Tests each route of GNRS API to confirm response content as expected. Other details as for ck\_tnrs.sh. **[PLANNED]**
nsr_ck.sh | Performance | Tests each route of NSR API to confirm response content as expected. Other details as for ck\_tnrs.sh. **[PLANNED]**
gvs_ck.sh | Performance | Tests each route of GVS API to confirm response content as expected. Other details as for ck\_tnrs.sh. **[PLANNED]**

<a name="usage"></a>
## Usage

### 1. up\_svc.sh

```
./up_svc.sh [-q] [-v] -u $URL
```

**Options:**

Option code | Option    | Purpose | Argument(s)
----------- | --------- | ------- | -----------
<nobr>-q&#160;\|&#160;--quiet</nobr> | Quiet | Suppress all progress messages | (none)
<nobr>-v&#160;\|&#160;--verbose</nobr> | Verbose | Echos additional information for debugging. Ignored if option -q also used | (none)
<nobr>-u&#160;\|&#160;--url</nobr> | URL | Base URL of the service being monitored. Do not include route-specific commands or parameters. For BIEN API, the base URL entered into a browser display a simple message identifying the service and confirming that it is online | Base URL of the service (required)
 
### 2. up\_svc_batch.sh

```
./up_svc_batch.sh [-q] [-m [$EMAIL_ADDRESS(ES)]]
```

**Options:**

Option code | Option    | Purpose | Argument(s)
----------- | --------- | ------- | -----------
<nobr>-q&#160;\|&#160;--quiet</nobr> | Quiet | Suppress all progress messages | (none)
<nobr>-m&#160;\|&#160;--mailto</nobr> | Send email | Send notification email if one or more errors detected. Both option and argument are optional. However parameter $EMAIL_ADDRESS(ES) must be preceeded by '-m' option code. If no -m used but no address supplied, with use default email set in params file. If -m omitted, only echos test results to terminal screen. | One or more email addresses separated by commas. Optional. If ommitted uses default email in params file.

### 3. ck_tnrs.sh

```
./ck_tnrs.sh [-i] [-q] [-v] [-u [URL]] [-m [EMAIL_ADDRESSES]]
```

**Options:**

Option code | Option    | Purpose | Argument(s)
----------- | --------- | ------- | -----------
<nobr>-i&#160;\|&#160;--initialize</nobr> | Initialize | Generate response reference files only, without testing or sending notifications. Use this mode during initial setup and any time you make changes to service that change response structure or content. Inspect each response file to verify that response is correct. | (none)
<nobr>-q&#160;\|&#160;--quiet</nobr> | Quiet | Suppress all progress messages | (none)
<nobr>-v&#160;\|&#160;--verbose</nobr> | Verbose | Echoes input data and respose for each test request. Ignored if -q option used | (none)
<nobr>-u&#160;\|&#160;--url</nobr> | URL | Base URL of the service being monitored. Do not include route-specific commands or parameters. For BIEN API, the base URL entered into a browser display a simple message identifying the service and confirming that it is online | Base URL of the service (required)
<nobr>-m&#160;\|&#160;--mailto</nobr> | Send email | Send notification email if one or more errors detected. Both option and argument are optional. However parameter $EMAIL_ADDRESS(ES) must be preceeded by '-m' option code. If no -m used but no address supplied, with use default email set in params file. If -m omitted, only echos test results to terminal screen. | One or more email addresses separated by commas. Optional. If ommitted uses default email in params file.


<a name="automation"></a>
## Automation using cron

The monitoring batch scripts should be set up to run as cron jobs. Instead of running as root or via your personal crontab, we recommend creating a user-specific cron file in directory `/etc/cron.d` and running the commands as a generic, low-level admin user with limited privileges. This makes the scripts easier to locate and avoids deletion by upgrades.

A cron entry that runs up\_svc_batch every hour on the hour using the default admin notification would look something like this:

```
0 * * * * bien /home/bien/admin/monitoring/up_svc_batch.sh -q -m
```


