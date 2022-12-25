#!/bin/bash

#####
#
# Script to find and report on VPN certificates that are expiring and create a CSV output
# Supports SMS / MDS - operates accordingly based on type of mgmt server
# Optional email notification can be enabled
#
# This script is not an official Check Point Software Technologies script
# Use of this script is at users own risk
# No support will be provided for this script by Check Point Software Technologies
#
# Author: Joe Audet
# Core Contributor: Igor_Demchenko (components of his script were used from: https://community.checkpoint.com/t5/Security-Gateways/Notify-when-certificate-expired/m-p/92189)
# Updated: 2022DEC24
#
# Tested on R81, R81.10, R81.20
#
#####

### User definable variables

# How far in advance you want to look for certs that will expire
AMOUNT_OF_DAYS=60;

### End user definable variables

# Load Check Point environment variables, exit if error
# Needs to be checked before any other code is run as some commands depend on the profile being loaded
if [ -r /etc/profile.d/CP.sh ]; then
  . /etc/profile.d/CP.sh
else
  echo "Could not source /etc/profile.d/CP.sh"
  exit
fi

### Global variables
VERSION="1.0"

# set this to the number of days you want to keep output files from this script
SELF_LOG_AGE=7;

# Ansi color code variables
ANSI_RED="\e[0;91m";
ANSI_GREEN="\e[0;32m";
ANSI_YELLOW="\e[0;33m";
ANSI_CYAN="\e[0;36m";
ANSI_RESET="\e[0m";

# Create a variable to store the script name in - used in notifications
SN=${0##*/};

TODAY=`date +"%Y%m%d"`;
DATETIME=$(date +"%Y%m%d_%H%M");
BASE_OUTPUT_DIR="/var/log/tmp/vpn_certs_reporting";
CSV_OUTPUT_FILE="${BASE_OUTPUT_DIR}/cert_expiration_dates_${TODAY}.csv";

# Array to store the certificate names in to iterate through later
CERT_NAMES=()

# Variables for email notification 
declare -a EXPIRING_CERTS;
SENDMAIL_EXECUTABLE=""
TEMP_MAIL_FILE="${BASE_OUTPUT_DIR}/$(hostname)_vpn_certs_expiring_${DATETIME}";

# Check if directories exists, if not create
[ ! -d $BASE_OUTPUT_DIR ] && mkdir -p "${BASE_OUTPUT_DIR}"

# Define SMTP settings file in same location script is being run
SMTP_SETTINGS_FILE="/var/log/smtp_settings";

### End global variable declarations

function log_message {
    MESSAGE=$1
    LOG_FILE=$2

    if [ -z "${2}" ]; then
        echo -e "${MESSAGE}"
    else
        echo -e "${MESSAGE}" >> "${LOG_FILE}"
    fi
}

function check_email_settings_file {

  if [ ! -f $SMTP_SETTINGS_FILE ]; then
    log_message "${ANSI_CYAN}${SMTP_SETTINGS_FILE}${ANSI_RESET} does not exist in the same directory as this script, creating"
    log_message "#SMTP server user defined variables used by ${SN}\n\n#Note: only one destination email can be used, suggest a distribution group\n\n### Change to true to enable email notification (all lowercase)\nSEND_EMAILS=false;\nMAIL_TO=\"\";\nMAIL_FROM=\"\";\nMAIL_SERVER_IP=\"\";" $SMTP_SETTINGS_FILE
  fi

  # Import SMTP Server user defined variables - should be in the same directory as the script
  source $SMTP_SETTINGS_FILE

  # If sending emails is enabled and settings file not present, create file with empty values
  if [ "${SEND_EMAILS,,}" = true ]; then

    # Check to make sure all SMTP Server variables have values, otherwise exit
    if [[ -z $MAIL_FROM || -z $MAIL_TO || -s $MAIL_SERVER_IP ]]; then
      log_message "SEND_EMAILS is enabled and one of the necessary SMTP Server user values is empty:"
      log_message ""
      log_message "Please check this file:"
      log_message "${ANSI_RED}${SMTP_SETTINGS_FILE}${ANSI_RESET}"
      log_message ""
      log_message "Make sure these variables all have values:"
      log_message "MAIL_FROM | MAIL_TO | MAIL_SERVER_IP"
      log_message ""
      exit
    fi
  fi
}

function email_message {

  # Display on command line for T/Sing
  log_message "${1}"
  # Append to $TEMP_MAIL_FILE which will be sent to users
  log_message "${1}" "${TEMP_MAIL_FILE}"

}

function find_certs {

  log_message "Checking for any VPN certificates that expire within the next ${ANSI_CYAN}${AMOUNT_OF_DAYS}${ANSI_RESET} days"

  # Collect certificate CN names for iteration, store in an array, sort
  readarray -t CERT_NAMES < <(cpca_client lscert -kind IKE -stat Valid | grep Subject | sed 's/Subject = //g;s/,$/\n/' | sed 's/,.*//' | sort)

  # Loop each certificate and collect the name and expiration date
  for CERT in "${CERT_NAMES[@]}"
  do
    :
    log_message "----------\nProcessing certificate: ${CERT}"
    # Get string with expiration date from certificate info
    CERT_INFO=`cpca_client lscert -stat Valid -dn "${CERT}" | grep Not_After`
    CERT_EXPIRATION_DATE=`cpca_client lscert -stat Valid -dn "${CERT}" | grep Not_After | awk -F '   '   '{print $2}' | sed 's/Not_After: //' | sed 's/  / /' | sed 's/ /,/g'`

    # Make list with expiration date, month and year
    EXPIRATION_DATE_SPLIT=$(python3 -c "lst='${CERT_INFO}'.split('Not_After:'); print(lst[1].split())")

    # Get expiration day
    EXPIRED_DATE=$( python3 -c "print($EXPIRATION_DATE_SPLIT[2])" )
    # Get expiration month
    EXPIRED_MONTH=$( python3 -c "print($EXPIRATION_DATE_SPLIT[1])" )
    # Get expiration year
    EXPIRED_YEAR=$( python3 -c "print($EXPIRATION_DATE_SPLIT[-1])" )

    # Find the difference between today and the expiration date, convert it to days
    let DIFF=(`date +%s -d "${EXPIRED_MONTH} ${EXPIRED_DATE} ${EXPIRED_YEAR}"`-`date +%s -d ${TODAY}`)/86400

    # If the amount of days between now and expiration date of the certificate is greater than the variable $AMOUNT_OF_DAYS, add it to the notification email, if not only display message to console
    if [ $DIFF -lt $AMOUNT_OF_DAYS ];
    then
      CERT_NAME="${CERT/CN=/}"
      if [ ${MDSVERUTIL+x} ]; then
        EXPIRING_MESSAGE="Domain: ${CMA} - ${CERT_NAME} VPN certificate will expire in ${DIFF} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
        log_message "CheckPoint VPN certificate - Domain: ${CMA} - ${ANSI_CYAN}${CERT_NAME}${ANSI_RESET} will expire in ${ANSI_RED}${DIFF}${ANSI_RESET} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
      else
        EXPIRING_MESSAGE="${CERT_NAME} VPN certificate will expire in ${DIFF} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
        log_message "CheckPoint VPN certificate - ${ANSI_CYAN}${CERT_NAME}${ANSI_RESET} will expire in ${ANSI_RED}${DIFF}${ANSI_RESET} days. Expires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
      fi
      EXPIRING_CERTS+=("$EXPIRING_MESSAGE")
    else
      if [ ${MDSVERUTIL+x} ]; then
        log_message "CheckPoint VPN certificate - Domain: ${CMA} - ${ANSI_CYAN}${CERT}${ANSI_RESET} good for ${ANSI_GREEN}${DIFF}${ANSI_RESET} more days\nExpires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
      else
        log_message "CheckPoint VPN certificate - ${ANSI_CYAN}${CERT}${ANSI_RESET} good for ${ANSI_GREEN}${DIFF}${ANSI_RESET} more days\nExpires on: ${EXPIRED_MONTH} ${EXPIRED_DATE}, ${EXPIRED_YEAR}"
      fi
    fi

    # Add ALL certificate CN, expiration date, and days left to expiration to a CSV file
    if [ ${MDSVERUTIL+x} ]; then
      log_message "${CMA},${CERT},${EXPIRED_MONTH},${EXPIRED_DATE},${EXPIRED_YEAR},${DIFF}" $CSV_OUTPUT_FILE
    else
      log_message "${CERT},${EXPIRED_MONTH},${EXPIRED_DATE},${EXPIRED_YEAR},${DIFF}" $CSV_OUTPUT_FILE
    fi
  done

}

function email_message {

  # Display on command line
  log_message "Email DEBUG info: Adding ${1} to: ${TEMP_MAIL_FILE}"
  # Append to $TEMP_MAIL_FILE which is used to send email
  log_message "$1" "$TEMP_MAIL_FILE"

}

function send_email {

  rm -f "${TEMP_MAIL_FILE}"
  touch "${TEMP_MAIL_FILE}"

  ### Start building the temp file we will use for email notifications
  email_message "${MAIL_FROM}\n${MAIL_TO}\n$(hostname) - Check Point VPN Certificate Expiration Notification ${TODAY}"
  email_message "CSV output files of all certs from the previous ${SELF_LOG_AGE} days can be found on $(hostname) in ${BASE_OUTPUT_DIR}\n\n"

  if (( ${#EXPIRING_CERTS[@]} )); then
    email_message "===== VPN CERTIFICATES EXPIRING WITHIN NEXT ${AMOUNT_OF_DAYS} DAYS =====\n"
    for ENTRY in "${EXPIRING_CERTS[@]}"
    do
      ### Add each expiring certificate warning to the body of the email
      email_message "${ENTRY}\n"
    done
  else
    # If no certificates expiring, make that the body
    email_message "No expiring certificates in next ${SELF_LOG_AGE} days"
  fi

  email_message "\n\nSent by:\nScript name: ${SN}\nVersion: ${VERSION}\nAt: ${DATETIME}\nCP Management Server: $(hostname)"

  # Send email notification
  log_message "\nEmail DEBUG info: Executing sendmail command:\n ${ANSI_CYAN}${SENDMAIL_EXECUTABLE} -t ${MAIL_SERVER_IP} -m ${TEMP_MAIL_FILE}${ANSI_RESET}"
  ${SENDMAIL_EXECUTABLE} -t "${MAIL_SERVER_IP}" -m "${TEMP_MAIL_FILE}"

  # Remove temporary files
  log_message "\nEmail Debug info: Removing temporary files:\n${ANSI_CYAN}${TEMP_MAIL_FILE}${ANSI_RESET}"
  rm -f "${TEMP_MAIL_FILE}"

}

# Cleanup the logs from this script running when past retention limit
function cleanup_output_files {
  cd "${BASE_OUTPUT_DIR}"
  SELFLOGLIST=$(find . -maxdepth 1 -mtime +$SELF_LOG_AGE -name "*.csv")

  log_message "\nCleaning up output folder"
  if [ "${SELFLOGLIST}" != "" ]; then
    for LOG in $SELFLOGLIST; do
      LOGFILENAME=$(echo "${LOG}" | sed 's/\.\///');
      log_message "Output file older then ${ANSI_CYAN}${SELF_LOG_AGE}${ANSI_RESET} days found: $(pwd)/${LOGFILENAME}"
      rm -f "${LOGFILENAME}"
    done
  else
    log_message "No output files over ${ANSI_CYAN}${SELF_LOG_AGE}${ANSI_RESET} days found in $(pwd) to cleanup\n"
  fi

}

function __main__ {
  check_email_settings_file

  # Remove output file (in case user runs multiple times on same day)
  rm -f "${CSV_OUTPUT_FILE}"
  touch "${CSV_OUTPUT_FILE}"

  # Header row of output CSV for sorting later
  if [ ${MDSVERUTIL+x} ]; then
    log_message "DOMAIN_SERVER_NAME,CERT_NAME,EXP_MONTH,EXP_DATE,EXP_YEAR,DAYS_LEFT" $CSV_OUTPUT_FILE
  else
    log_message "CERT_NAME,EXP_MONTH,EXP_DATE,EXP_YEAR,DAYS_LEFT" $CSV_OUTPUT_FILE
  fi

  if [ ${MDSVERUTIL+x} ]; then
    log_message "MDS Detected - processing all Domains"
    # Read domain names into array and sort them - otherwise output will be sorted in order of domain creation
    readarray -t AllDomains < <(printf '%s\n' $($MDSVERUTIL AllCMAs) | sort)
    for CMA in ${AllDomains[*]}; do
        log_message "\n=======================\n\nProcessing ${CMA}"
        mdsenv "${CMA}"
        find_certs $CMA
        log_message "\nCompleted ${CMA}"
    done
    # Return to default MDS environment
    mdsenv
    SENDMAIL_EXECUTABLE="${MDS_FWDIR}/bin/sendmail"
  else
    log_message "SMS Detected - processing"
    find_certs
    SENDMAIL_EXECUTABLE="${FWDIR}/bin/sendmail"
  fi

  # Display message of where CSV file is located to console
  log_message "\n=======================\n"
  log_message "All certificate names and their expiration dates were stored in the following CSV file:\n${ANSI_CYAN}${CSV_OUTPUT_FILE}${ANSI_RESET}"

  # Cleanup output files
  cleanup_output_files

  # Send notification email if enabled, otherwise notify user email notifications are disabled
  if [ "${SEND_EMAILS,,}" = true ]; then
    log_message "=====\n${ANSI_CYAN}Sending notification emails${ANSI_RESET}\n=====\n"
    send_email
  else
    log_message "=====\nEmail Notifications are disabled\nChange the following variable in ${ANSI_ANSI}${SMTP_SETTINGS_FILE}${ANSI_RESET} to true: SEND_EMAILS=false;\n=====\n";
  fi  
}

### END OF FUNCTION DECLARATIONS

# Get the ball rolling
__main__
