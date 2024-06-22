#!/bin/bash
#
# Security Gateway Uptime Inventory - Bash script for Check Point Multi-Domain Servers (MDS) only
#
# Script Author : Joe Audet
#
# This script is not an official Check Point Software Technologies script
# Use of this script is at users own risk
# No support will be provided for this script by Check Point Software Technologies
#
# Created: 2024MAY14
# Updated: 2024JUN22  
# Version 0.3
#
# Tested in R81.20 MDS
#
# cpmiquerybin component and filter from Kaspars Zibarts script: https://community.checkpoint.com/t5/API-CLI-Discussion-and-Samples/Security-Gateway-Inventory/td-p/32547
#
#####

if [[ -e /etc/profile.d/CP.sh ]]; then source /etc/profile.d/CP.sh; else echo "Unsupported Environment"; exit 1; fi
if ! [[ `echo $MDSDIR | grep mds` ]]; then echo "Not a Multi-Domain Server (MDS)!"; exit 1; fi

# Create a variable to store the script name in - used in notifications
SN=${0##*/};

### User definable variables

# set this to the number of days you want to keep output files from this script
SELF_LOG_AGE=7

# End user definable variables

### Global variables
TODAY=`date +"%Y%m%d"`;
DATETIME=$(date +"%Y%m%d_%H%M%S");
BASE_OUTPUT_DIR="/var/log/tmp/gateway_uptime_reporting";
CSV_OUTPUT_FILE="${BASE_OUTPUT_DIR}/gateway_uptime_report_${DATETIME}.csv";
GATEWAY_TEMP_FILE="${BASE_OUTPUT_DIR}/gateways.txt"

#Check if directories exists, if not create
[ ! -d $BASE_OUTPUT_DIR ] && mkdir -p "$BASE_OUTPUT_DIR"

#Check to make sure CSV output file exists, if not create, if exists, erase
if [ ! -f $CSV_OUTPUT_FILE ]; then
    echo "Creating CSV output file ${CSV_OUTPUT_FILE}"
    echo -e "CMA_SERVER_NAME,GW_NAME,GW_IP,UPTIME_CLEAN" >> $CSV_OUTPUT_FILE
fi

## Start functions ##

function get_uptime {
    for CMA_NAME in $($MDSVERUTIL AllCMAs); do
        # Make sure we dont have any remnants
        rm -f $GATEWAY_TEMP_FILE
        # Change to the MDS environment
        mdsenv $CMA_NAME
        # Use the builtin binary to query all gateway objects with a filter, store the output in a temp txt file
        cpmiquerybin attr "" network_objects " (type='cluster_member' & vsx_cluster_member='true' & vs_cluster_member='true') | (type='cluster_member' & (! vs_cluster_member='true')) | (vsx_netobj='true') | (type='gateway'&cp_products_installed='true' & (! vs_netobj='true') & connection_state='communicating')" -a __name__,ipaddr > $GATEWAY_TEMP_FILE

        # Read in the temp text file, and parse the attributes to use them
        while read line; do
            GW=`echo "$line" | awk '{print $1}'`
            IP=`echo "$line" | awk '{print $2}'`
            # Use cprid_util SK101047 to get the uptime from the gateways
            UPTIME1=`cprid_util -server $IP -verbose rexec -rcmd bash -c "uptime"`
            # Convert the output to a form we want base on whether gateway has been up for more than 24 hours
            UPTIME=`echo $UPTIME1 | awk -F'( |,|:)+' '{d=h=m=0; if ($6=="min") m=$5; else {if ($6~/^day/) {d=$5;h=$7;m=$8} else {h=$5;m=$6}}} {print d+0,"days",h+0,"hours",m+0,"minutes"}'`
            # Display output on terminal
            echo "$CMA_NAME,$GW,$IP,$UPTIME"
            # Append output to output file
            echo "$CMA_NAME,$GW,$IP,$UPTIME" >> $CSV_OUTPUT_FILE
        done < $GATEWAY_TEMP_FILE

    done
    # Cleanup temp files
    rm -f $GATEWAY_TEMP_FILE

    # Cleanup output files
    cleanup_output_files

    # Exit cleanly when done
    exit 0
}

#Cleanup the logs from this script running when past retention limit
function cleanup_output_files {
    cd "$BASE_OUTPUT_DIR"
    SELFLOGLIST=$(find . -maxdepth 1 -mtime +$SELF_LOG_AGE -name "*.csv")

    echo ""
    echo -e "Cleaning up output over $SELF_LOG_AGE days old"
    if [ "$SELFLOGLIST" != "" ]; then
        for LOG in $SELFLOGLIST; do
            LOGFILENAME=$(echo "$LOG" | sed 's/\.\///');
            echo "Output file older then $SELF_LOG_AGE days found: $(pwd)/${LOGFILENAME}"
            rm -f "$LOGFILENAME"
        done
    else
        echo -e "No output files over $SELF_LOG_AGE days found in $(pwd) to cleanup\n"
    fi

}

## END OF FUNCTION DECLARATIONS ##

#Get things started
get_uptime