#!/bin/bash

#####
# Script to run where-used against all DOMAIN's in an MDS server
# Output is simple JSON only, no filtering
##

#Load Check Point environment variables, exit if error
    if [ -r /etc/profile.d/CP.sh ]; then
       . /etc/profile.d/CP.sh
else
    echo "Could not source /etc/profile.d/CP.sh"
    exit
fi

SN=${0##*/};

if [[ -z $1 || $1 = "-h" || $1 = "--help" ]]; then
    echo ""
    echo "Please enter an object name you want to search for"
    echo ""
    echo "Ex: $SN <objectname>"
    exit
fi

JQ=${CPDIR}/jq/jq
DOMAINS_FILE="domains.json"

#Check if variable empty, if so indicates a smartcenter not an MDS
if [ -z ${MDSVERUTIL+x} ]; then
       echo "Smartcenter detected"
       echo ""

else

    echo 'Getting a list of domains...'
    mgmt_cli -r true -d MDS show domains limit 500 --format json > $DOMAINS_FILE
    if [ $? -eq 1 ]; then
      echo "Error getting list of domains. Aborting!"
      exit 1
    fi
    DOMAIN_NAMES=($($JQ -r ".objects[] | .name" $DOMAINS_FILE))

    for DOMAIN in ${DOMAIN_NAMES[@]}
    do
        echo "=========================="
        echo "Searching ${DOMAIN} for $1"
        echo ""
        mgmt_cli -r true login domain $DOMAIN > "${DOMAIN}_sid.txt"
        mgmt_cli where-used name $1 --format json -s "${DOMAIN}_sid.txt"
        echo ""
        echo "Logging out of ${DOMAIN}"
        echo ""
        mgmt_cli logout -s "${DOMAIN}_sid.txt"
        rm -f "${DOMAIN}_sid.txt"
    done
fi