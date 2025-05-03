#!/bin/bash

#####
#
# Script to find and report on gateway Mgmt MAC address and serial number
# Currently SMS only
#
# This script is not an official Check Point Software Technologies script
# Use of this script is at users own risk
# No support will be provided for this script by Check Point Software Technologies
#
# Author: Joe Audet
# Created: 2025MAY02
# Updated: 2025MAY02
# Version 1
#
# Tested in R82
#
#####

#Load Check Point environment variables, exit if error
if [ -r /etc/profile.d/CP.sh ]; then
    /etc/profile.d/CP.sh
else
    echo "Could not source /etc/profile.d/CP.sh"
    exit
fi

DATETIME=$(date +"%Y%m%d_%H%M%S");
BASE_OUTPUT_DIR="/var/log/tmp/gateway_serial_reporting";
CSV_OUTPUT_FILE="${BASE_OUTPUT_DIR}/gateway_serial_report_${DATETIME}.csv";

#Array to store the gateway names in to iterate through later
SIMPLE_GATEWAY_NAMES=()
CLUSTER_MEMBER_NAMES=()

#Check if directories exists, if not create
[ ! -d $BASE_OUTPUT_DIR ] && mkdir -p "$BASE_OUTPUT_DIR"

#Check to make sure CSV output file exists, if not create, if exists, erase
if [ ! -f $CSV_OUTPUT_FILE ]; then
    echo "Creating CSV output file ${CSV_OUTPUT_FILE}"
    echo -e "GW_NAME,IP,MGMT_MAC,PLATFORM,SERIAL" >> $CSV_OUTPUT_FILE
fi

function find_gateway_serials {
    echo "Collecting gateway names"
    #Collect simple-gateway object names
    SIMPLE_GATEWAY_NAMES=`mgmt_cli -r true show gateways-and-servers limit 500 --format json | jq -r '.objects[] | select(.type=="simple-gateway").name'`
    #show cluster-member API call requires UID, does not work with name
    CLUSTER_MEMBER_UID=`mgmt_cli -r true show gateways-and-servers limit 500 --format json | jq -r '.objects[] | select(.type=="cluster-member").uid'`

    #Store gateway names in a variable after parsing on new line returns from the JQ output
    GWNAMES=()
    IFS=$'\n' read -r -a GWNAMES <<< ${SIMPLE_GATEWAY_NAMES[@]}
    #Store cluster members UIDs in a variable, parsing on new line returns from the JQ output inheriting the IFS above
    CLUSTER_MEMBERS=()
    read -r -a CLUSTER_MEMBERS <<< ${CLUSTER_MEMBER_UID[@]}

    echo "Looping through gateway list to retrieve the Mgmt interface MAC address, Platform, Model and Serial number"

    echo "Processing simple-gateway objects:"
    for each in $GWNAMES
    do
        IP=`mgmt_cli -r true show simple-gateway name $each --format json | jq -r '."ipv4-address"'`
        echo "Connecting to ${each} at ${IP}"
        MAC=`cprid_util -server $IP -verbose rexec -rcmd bash -c "ip link show dev Mgmt"`
        MAC=$(awk '/link/{print $2}' <<< $MAC)
        ASSETS=`cprid_util -server $IP -verbose rexec -rcmd bash -c 'clish -c "show asset all"'`
        PLATFORM=$(grep Platform <<< $ASSETS)
        MODEL=$(grep ^Model <<< $ASSETS)
        SERIAL=$(grep Serial <<< $ASSETS)
        OUTPUT="${each},${IP},${MAC},${PLATFORM},${MODEL},${SERIAL}"
        echo $OUTPUT >> $CSV_OUTPUT_FILE
    done

    #show cluster-member API call requires UID, does not work with name
    echo "Processing cluster-member objects:"
    for each in "${CLUSTER_MEMBERS[@]}"
    do
        MEMBER_NAME=`mgmt_cli -r true show cluster-member uid $each --format json | jq -r '."name"'`
        IP=`mgmt_cli -r true show cluster-member uid $each --format json | jq -r '."ip-address"'`
        echo "Connecting to ${MEMBER_NAME} at ${IP}"
        MAC=`cprid_util -server $IP -verbose rexec -rcmd bash -c "ip link show dev Mgmt"`
        MAC=$(awk '/link/{print $2}' <<< $MAC)
        ASSETS=`cprid_util -server $IP -verbose rexec -rcmd bash -c 'clish -c "show asset all"'`
        PLATFORM=$(grep Platform <<< $ASSETS)
        MODEL=$(grep ^Model <<< $ASSETS)
        SERIAL=$(grep Serial <<< $ASSETS)
        OUTPUT="${MEMBER_NAME},${IP},${MAC},${PLATFORM},${MODEL},${SERIAL}"
        echo $OUTPUT >> $CSV_OUTPUT_FILE

    done

    echo -e "\n\nYou can find the export file here:\n${CSV_OUTPUT_FILE}"
}

#Run main function to find serials
find_gateway_serials
