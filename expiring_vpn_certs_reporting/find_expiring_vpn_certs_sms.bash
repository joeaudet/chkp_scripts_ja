#!/bin/bash

#####
#
# Script to find and report on VPN certificates that are expiring and create a CSV output
#
# This script is not an official Check Point Software Technologies script
# Use of this script is at users own risk
# No support will be provided for this script by Check Point Software Technologies
#
# Author: Joe Audet
# Created: 2022OCT04
#
#####

# Set Check Point environment variables
if [ -f /opt/CPshared/5.0/tmp/.CPprofile.sh ]; then
 . /opt/CPshared/5.0/tmp/.CPprofile.sh
fi

if [ -f /etc/rc.d/rc.local.user ]; then
  . /etc/rc.d/rc.local.user
fi

# Ansi color code variables
ANSI_RED="\e[0;91m";
ANSI_GREEN="\e[0;32m";
ANSI_YELLOW="\e[0;33m";
ANSI_RESET="\e[0m";

# Create a variable to store the script name in - used in notifications
SN=${0##*/};

### User definable variables

#How far in advance you want to look for certs that will expire
AMOUNT_OF_DAYS=60;

# set this to the number of days you want to keep output files from this script
SELF_LOG_AGE=7

# End user definable variables

### Global variables
TODAY=`date +"%Y%m%d"`;
DATETIME=$(date +"%Y%m%d_%H%M%S");
BASE_OUTPUT_DIR="/var/log/tmp/vpn_certs_reporting";
CSV_OUTPUT_FILE="${BASE_OUTPUT_DIR}/cert_expiration_dates_${TODAY}.csv";

#Array to store the certificate names in to iterate through later
CERT_NAMES=()

#Variables for notification of upload activities
declare -a EXPIRING_CERTS;
TEMP_MAIL_FILE="${BASE_OUTPUT_DIR}/$(hostname)_vpn_certs_expiring_${DATETIME}";

#Check if directories exists, if not create
[ ! -d $BASE_OUTPUT_DIR ] && mkdir -p "$BASE_OUTPUT_DIR"

#Define SMTP settings file in same location script is being run
SMTP_SETTINGS_FILE="/var/log/smtp_settings"

###Change to true to enable email notification
SEND_EMAILS=false;

###End global variable declarations

#If sending emails is enabled, check for settings file, if not present create it with empty values
if [ "$SEND_EMAILS" = true ]; then
    if [ ! -f $SMTP_SETTINGS_FILE ]; then
        echo "$SMTP_SETTINGS_FILE does not exist in the same directory as this script, creating"
        echo -e "#SMTP server user defined variables used by $SN\n\n#Note: only one destination email can be used, suggest a distribution group\n\nMAIL_TO=\"\"\nMAIL_FROM=\"\"\nMAIL_SERVER_IP=\"\"" >> $SMTP_SETTINGS_FILE
    fi

    #Import SMTP Server user defined variables - should be in the same directory as the script
    source $SMTP_SETTINGS_FILE

    #Check to make sure all SMTP Server variables have values, otherwise exit
    if [[ -z $MAIL_FROM || -z $MAIL_TO || -s $MAIL_SERVER_IP ]]; then
        echo "SEND_EMAILS is enabled and one of the necessary SMTP Server user values is empty:"
        echo ""
        echo "Please check this file:"
        echo -e "${ANSI_RED}$(pwd)/${SMTP_SETTINGS_FILE}${ANSI_RESET}"
        echo ""
        echo "Make sure these variables all have values:"
        echo "MAIL_FROM | MAIL_TO | MAIL_SERVER_IP"
        echo ""
        exit
    fi
else
    echo -e "=====\nEmail Notifications are disabled\nChange the following variable in this script to true: SEND_EMAILS=false;\n=====\n";
fi

function email_message {

    #Display on command line for T/Sing
    echo -e "${1}"
    #Append to $TEMP_MAIL_FILE which will be sent to users
    echo -e "$1" >> "$TEMP_MAIL_FILE"

}

function find_certs {

#Header row of output CSV for sorting later
echo "CERT_NAME,EXP_MONTH,EXP_DATE,EXP_YEAR,DAYS_LEFT" > $CSV_OUTPUT_FILE

echo -e "Checking for any VPN certificates that expire within the next ${AMOUNT_OF_DAYS} days\n++++++++++\n"

# Collect certificate CN names for iteration and store in an array
readarray -t CERT_NAMES < <(cpca_client lscert -kind IKE -stat Valid | grep Subject | sed 's/Subject = //g;s/,$/\n/' | sed 's/,.*//')

# Loop each certificate and collect the name and expiration date
for CERT in "${CERT_NAMES[@]}"
do
    :
    echo -e "----------\nProcessing certificate: $CERT"
        #get string with expiration date from certificate info
        CERT_INFO=`cpca_client lscert -stat Valid -dn "$CERT" | grep Not_After`
        CERT_EXPIRATION_DATE=`cpca_client lscert -stat Valid -dn "$CERT" | grep Not_After | awk -F '   '   '{print $2}' | sed 's/Not_After: //' | sed 's/  / /' | sed 's/ /,/g'`

        #make list with expiration date, month and year
        EXPIRATION_DATE_SPLIT=$(python -c "lst='$CERT_INFO'.split('Not_After:'); print(lst[1].split())")

        #get expiration day
        EXPIRED_DATE=$( python -c "print($EXPIRATION_DATE_SPLIT[2])" )
        #get expiration month
        EXPIRED_MONTH=$( python -c "print($EXPIRATION_DATE_SPLIT[1])" )
        #get expiration year
        EXPIRED_YEAR=$( python -c "print($EXPIRATION_DATE_SPLIT[-1])" )

        # Find the difference between today and the expiration date, convert it to days
        let DIFF=(`date +%s -d "${EXPIRED_MONTH} ${EXPIRED_DATE} ${EXPIRED_YEAR}"`-`date +%s -d $TODAY`)/86400

        # If the amount of days between now and expiration date of the certificate is greater than the variable $AMOUNT_OF_DAYS, add it to the notification email, if not only display message to console
        if [ $DIFF -lt $AMOUNT_OF_DAYS ];
        then
            CERT_NAME="${CERT/CN=/}"
            EXPIRING_MESSAGE="${CERT_NAME} VPN certificate will expire in ${DIFF} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
            echo -e "CheckPoint VPN certificate for: ${CERT_NAME} will expire in ${ANSI_RED}${DIFF}${ANSI_RESET} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}\n"
            EXPIRING_CERTS+=("$EXPIRING_MESSAGE")
        else
            echo -e "CheckPoint VPN certificate ${ANSI_GREEN}${CERT}${ANSI_RESET} good for ${ANSI_GREEN}${DIFF}${ANSI_RESET} more days\nExpires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR} \n"
        fi

        # Add ALL certificate CN, expiration date, and days left to expiration to a CSV file
        echo "${CERT},${EXPIRED_MONTH},${EXPIRED_DATE},${EXPIRED_YEAR},${DIFF}" >> $CSV_OUTPUT_FILE
done

    # Display message of where CSV file is located to console
    echo -e "All certificate names and their expiration dates were stored in the following CSV file: ${ANSI_YELLOW}$CSV_OUTPUT_FILE${ANSI_RESET}\n"

    # Cleanup output files
    cleanup_output_files

    # Send notification email if enabled
    if [ "$SEND_EMAILS" = true ]; then
        echo "Sending notification emails"
        send_email
    fi

}

function email_message {

    #Display on command line
    echo -e "Adding ${1} to: ${TEMP_MAIL_FILE}"
    #Append to $TEMP_MAIL_FILE which will be sent to users
    echo -e "$1" >> "$TEMP_MAIL_FILE"

}

function send_email {

    rm -f "$TEMP_MAIL_FILE"
    touch "$TEMP_MAIL_FILE"

    ### Start building the temp file we will use for email notifications
    email_message "$MAIL_FROM\n$MAIL_TO\n$(hostname) VPN Certificate Expiriation Notification ${TODAY}"
    email_message "CSV output files of all certs from the previous ${SELF_LOG_AGE} days can be found on $(hostname) in ${BASE_OUTPUT_DIR}\n\n"

    if (( ${#EXPIRING_CERTS[@]} )); then
        email_message "===== VPN CERTIFICATES EXPIRING WITHIN NEXT ${AMOUNT_OF_DAYS} DAYS =====\n"
        for ENTRY in "${EXPIRING_CERTS[@]}"
        do
            ### Add each expiring certificate warning to the body of the email
            email_message "$ENTRY\n"
        done
    else
        # If no certificates expiring, make that the body
        email_message "No expiring certificates in next ${SELF_LOG_AGE} found running $SN at ${DATETIME}"
    fi

    # Send email notification
    "$FWDIR"/bin/sendmail -t "$MAIL_SERVER_IP" -m "$TEMP_MAIL_FILE"

    #Remove temporary files
    rm -f "$TEMP_MAIL_FILE"
    rm -f "$TEMP_UPLOAD_LOG_FILE"

}

#Cleanup the logs from this script running when past retention limit
function cleanup_output_files {
    cd "$BASE_OUTPUT_DIR"
    SELFLOGLIST=$(find . -maxdepth 1 -mtime +$SELF_LOG_AGE -name "*.log")

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

#Run main function to find scripts
find_certs
