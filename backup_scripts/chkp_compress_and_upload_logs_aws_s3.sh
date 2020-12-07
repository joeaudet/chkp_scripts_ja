#!/bin/bash

#####
# Log bundler (Matt Hill)
#
# Script to bundle up the logfile and associated logfile pointers that are
#  generated each day and compress them using gzip on maximal compression.
# When run on a smartcenter in auto bundle mode it will find any checkpoint
#  log older than $LOG_AGE (set below) and bundle that logfile and pointers.
# When run on an MDS it will do that for each CMA.
##
# 2012-08-30 MH - initial version
# 2012-09-01 MH - modified to require command line options and to add test
#                 and manual modes. Added help text. Now updates timestamp
#                 of archive to be that of logfile.
# 2013-07-26 MH - added deletion of old logs, controlled by ARCHIVE_AGE variable
#
# 2020-08-20 JA - Joe Audet used Matt's script as a basis for an expanded version
# 2020-08-20 JA - Add in AWS S3 storage upload capabilities
# 2020-08-27 JA - Modified do_bundle to put each log file in its own archive
#                 to ensure no issues with 2GB file creation limit
#               - Changed autobundled to use $($MDSVERUTIL AllCMAs) instead of creating an array of CMA's
#               - Added in S3 MD5 verification of files
# 2020-09-30 JA - Added in functionality to list all CMA names
#               - Added in ability to specify individual CMA name or loop all CMA names
#               - Added command to test function to add output to output file per CMA for review before running
#               - Updated S3 upload mechanism to create the following directory structure for uploads: CMA/YEAR/MONTH/FILES
# 2020-10-01 JA - Added ANSI color codes for some output messages
#               - Moved AWS BUCKET and keys to separate file that is imported so not overwritten on updates
#               - Check if $KEYS_FILE exists, if not create it with empty values and alert user to fill in those values
# 2020-10-02 JA - Updated AWS S3 upload to capture and parse HTTP code to determine if file properly uploaded
# 2020-10-09 JA - Added in functions to enable email notifications, with separate settings file for SMTP settings and a check if present
##


# Ansi color code variables
ANSI_RED="\e[0;91m";
ANSI_RESET="\e[0m";

SN=${0##*/};
KEYS_FILE="aws_keys";
HTTP_RESPONSE="";

TODAY=$(date +"%Y%m%d");
DATETIME=$(date +"%Y%m%d_%T");
OUTPUT_DIR="/var/log/tmp/compress_and_upload_output";
#Check if directory exists, if not create it
[ ! -d $OUTPUT_DIR ] && mkdir -p "$OUTPUT_DIR"

#Variables for notification of upload activities
declare -a SUCCESSFUL_UPLOADS;
declare -a UPLOAD_ERRORS;
TEMP_MAIL_FILE="${OUTPUT_DIR}/$(hostname)_s3_upload_email_${DATETIME}";
SUCCESS_LOG="${OUTPUT_DIR}/$(hostname)_s3_upload_${DATETIME}_success.log";
ERROR_LOG="${OUTPUT_DIR}/$(hostname)_s3_upload_${DATETIME}_error.log";
SMTP_SETTINGS_FILE="smtp_settings"
###User defined environment specific settings for email notification
SEND_EMAILS=false;
MAIL_TO="destinationemail@domain.com";
MAIL_FROM="sourceemail@domain.com";
MAIL_SERVER_IP="x.x.x.x";

if [ ! -f $KEYS_FILE ]; then
    echo "$KEYS_FILE does not exist in the same directory as this script, creating"
    echo -e "#AWS S3 user defined variables used by $SN\nBUCKET=\"\"\nS3KEY=\"\"\nS3SECRET=\"\"" >> $KEYS_FILE
fi

#Import AWS S3 user defined variables - should be in the same directory as the script
source $KEYS_FILE

#Check to make sure all S3 variables have values, otherwise exit
if [[ -z $BUCKET || -z $S3KEY || -s $S3SECRET ]]; then
    echo "One of the necessary AWS S3 user values is empty"
    echo ""
    echo "Please check this file:"
    echo -e "${ANSI_RED}$(pwd)/${KEYS_FILE}${ANSI_RESET}"
    echo ""
    echo "Make sure these variables all have values:"
    echo "BUCKET | S3KEY | S3SECRET"
    echo ""
    exit
fi

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

fi

#As of 2020-10-01 - not able to figure out correct CA cert formatting
#CACERT not used yet
#CACERT=/home/admin/awss3_cacert.pem

# set this to the number of days that you wish to keep logs unbundled for
LOG_AGE=30

# this one is the number of days to upload and delete archive bundles after (set to 0 to disable)
ARCHIVE_AGE=90

## FUNCTIONS ###
function upload_to_aws_s3 {
FILE=$1
#AWSPATH format - CMA/YEAR/MONTH
AWSPATH="${2}/${3}/${4}"
COMMAND_OUTPUT_FILE=$5
FILENAME=$(echo $FILE | sed 's/\.\///');\
DATEVALUE=`date -R`
RESOURCE="/${BUCKET}/${AWSPATH}/${FILE}"
CONTENTTYPE="application/x-compressed-tar"
STRINGTOSIGN="PUT\n\n${CONTENTTYPE}\n${DATEVALUE}\n${RESOURCE}"
MD5SUM=$($MDS_CPDIR/bin/cpopenssl md5 -binary "$FILE" | base64)
S3_BUCKET="https://${BUCKET}.s3.amazonaws.com/${AWSPATH}/${FILE}"
SIGNATURE=`echo -en ${STRINGTOSIGN} | $MDS_CPDIR/bin/cpopenssl sha1 -hmac ${S3SECRET} -binary | base64`

    #Check if $DEMO equals yes, if so do not run the commands, echo them to an output file
    if [[ $DEMO = "echo" ]]; then
        echo "curl_cli -s -k -o /dev/null -D - -X PUT -T "${FILENAME}" \
        -H "Host: ${BUCKET}.s3.amazonaws.com" \
        -H "Date: ${DATEVALUE}" \
        -H "Content-Type: ${CONTENTTYPE}" \
        -H "Content-MD5=$MD5SUM" \
        -H "Authorization: AWS ${S3KEY}:${SIGNATURE}" \
        -H "Connection: close" \
        ${S3_BUCKET}"  >> $COMMAND_OUTPUT_FILE;
    else
        HTTP_RESPONSE="$(curl_cli -s -k -o /dev/null -D - -X PUT -T "${FILENAME}" \
        -H "Host: ${BUCKET}.s3.amazonaws.com" \
        -H "Date: ${DATEVALUE}" \
        -H "Content-Type: ${CONTENTTYPE}" \
        -H "Content-MD5=$MD5SUM" \
        -H "Authorization: AWS ${S3KEY}:${SIGNATURE}" \
        -H "Connection: close" \
        ${S3_BUCKET} )"

        #Parse the response output looking for the HTTP code, grab the number and text only, strip any special characters
        RESPONSE_CODE="$(echo $HTTP_RESPONSE | awk '$1 ~ /^HTTP/ { print NR,$0 }' | cut -f 3,4 -d ' ' | tr -d '\n\r\t' )"

        if [[ $RESPONSE_CODE == "200 OK" ]] || [[ $RESPONSE_CODE == "100 Continue" ]] ; then
            SUCCESS_MESSAGE="$(hostname) - $(pwd)/${FILE} uploaded successfully to ${S3_BUCKET}"
            SUCCESSFUL_UPLOADS+=("$SUCCESS_MESSAGE")
            echo $SUCCESS_MESSAGE
            echo $SUCCESS_MESSAGE >> $SUCCESS_LOG
        else
            ERROR_MESSAGE="$(hostname) - $(pwd)/${FILE} had an error uploading to ${S3_BUCKET} - please fix and retry"
            UPLOAD_ERRORS+=("$ERROR_MESSAGE")
            echo $ERROR_MESSAGE
            echo $ERROR_MESSAGE >> $ERROR_LOG
        fi

    fi
}

# Bundles log and pointers for logfile passed in as sole parameter
function do_bundle {
    LOGFILE=$1
    CMA=$2
    COMMAND_OUTPUT_FILE="$3"
    LOGDATE=""
    LOGDATE=$(echo $LOGFILE | sed 's/\.\///' | sed 's/_[0-9]*\.[a-z]*//');\
    LOGFILENAME=$(echo $LOGFILE | sed 's/\.\///');\
    LOGFILEWITHOUTEXT=$(echo $LOGFILENAME | cut -f 1 -d '.')
    ARCHIVEFILENAME="${LOGFILENAME}_${CMA}.tar.gz"

    if [ -e ${LOGFILENAME}.tar.gz ]; then
            echo "${LOGFILENAME}.tar.gz already exists, skipping"
            continue
    fi

    #fix timestamp of newly created archive file to match the modify date @ 23:59 of the original log file
    ORIGINALMODIFYDATE=$(echo $LOGFILEWITHOUTEXT | cut -f 1,2,3 -d '-' | cut -f 1 -d '_'  | sed 's/\-//g')

    if [[ $DEMO = "echo" ]]; then
       echo "touch -t ${ORIGINALMODIFYDATE}"2359" $ARCHIVEFILENAME" >> $COMMAND_OUTPUT_FILE
       echo "tar czvf $ARCHIVEFILENAME --exclude=${ARCHIVEFILENAME} --remove-files ${LOGFILEWITHOUTEXT}*" >> $COMMAND_OUTPUT_FILE;
       echo "touch -t ${ORIGINALMODIFYDATE}"2359" $ARCHIVEFILENAME" >> $COMMAND_OUTPUT_FILE

    else
       echo "Log files for ${LOGFILEWITHOUTEXT} archived into $ARCHIVEFILENAME" >> $SUCCESS_LOG
       touch -t ${ORIGINALMODIFYDATE}"2359" $ARCHIVEFILENAME
       tar czvf $ARCHIVEFILENAME --exclude=${ARCHIVEFILENAME} --remove-files ${LOGFILEWITHOUTEXT}* ;\
       touch -t ${ORIGINALMODIFYDATE}"2359" $ARCHIVEFILENAME
    fi

}

# For autobundle (and test) finds all logfiles of interest and calls do_bundle
#  on them.
function bundle_loop {
   cd $FWDIR/log
   CMA=$1
   LOGLIST=`find . -maxdepth 1 -mtime +$LOG_AGE -name "*.log"`
   ARCHIVELIST=`find . -maxdepth 1 -mtime +$ARCHIVE_AGE -name "*.gz"`


   if [[ $DEMO_SUFFIX == "yes" ]]; then
       #Output file for DEMO option to echo commands to for review
       COMMAND_OUTPUT_FILE="${OUTPUT_DIR}/${CMA}_compress_upload_output.txt"
       rm -f $COMMAND_OUTPUT_FILE
       echo "cd $(pwd)" >> $COMMAND_OUTPUT_FILE
   fi

   if [ "$LOGLIST" != "" ]; then
        for LOG in $LOGLIST; do
            do_bundle $LOG $CMA $COMMAND_OUTPUT_FILE
        done
    else
        NO_LOG_MESSSAGE="No logs over $LOG_AGE days to compress found in $(pwd)"
        echo $NO_LOG_MESSSAGE
        echo $NO_LOG_MESSSAGE >> $SUCCESS_LOG
    fi

   if [ "$ARCHIVELIST" != "" ]; then
        for ARCHIVE in $ARCHIVELIST; do
            ARCHIVE=$(echo $ARCHIVE | sed 's/\.\///');\
            echo "Archive older then $ARCHIVE_AGE days found: $(pwd)/${ARCHIVE}"
            YEAR=$(echo $ARCHIVE | cut -f 1 -d '-')
            MONTH=$(echo $ARCHIVE | cut -f 2 -d '-')
            upload_to_aws_s3 $ARCHIVE $CMA $YEAR $MONTH $COMMAND_OUTPUT_FILE
        done
    else
        NO_ARCHIVE_MESSSAGE="No archives over $ARCHIVE_AGE days to upload found in $(pwd)"
        echo $NO_ARCHIVE_MESSSAGE
        echo $NO_ARCHIVE_MESSSAGE >> $SUCCESS_LOG
    fi

#Still working out upload validation logic to confirm successful upload before deleting files automatically on 2020SEP30 - JA
#Logic to confirm successful upload finished - this will be rewritten into a separate function called by the upload function
#    if [ "$ARCHIVE_AGE" -gt 0 ]; then
#        DELETELIST=`find . -mtime +$ARCHIVE_AGE -name "*.gz"`
#        if [[ $DEMO = "echo" ]]; then
#            for BUNDLE in $DELETELIST; do
#                BUNDLE=$(echo $BUNDLE | sed 's/\.\///');\
#                echo "/bin/rm -v $BUNDLE" >> $COMMAND_OUTPUT_FILE
#            done
#        else
#            for BUNDLE in $DELETELIST; do
#                BUNDLE=$(echo $BUNDLE | sed 's/\.\///');\
#                /bin/rm -v $BUNDLE
#            done
#        fi
#    fi
}

# Detects if on Smartcenter or Provider-1 and runs bundle_loop for each
# CMA or just once for Smartcenter
function autobundle {
    #Load Check Point environment variables, exit if error
    if [ -r /etc/profile.d/CP.sh ]; then
       . /etc/profile.d/CP.sh
    else
        echo "Could not source /etc/profile.d/CP.sh"
        exit
    fi

    #Check if variable empty, if so indicates a smartcenter not an MDS
    if [ -z ${MDSVERUTIL+x} ]; then
       echo "Smartcenter detected"
       echo ""

       bundle_loop $CMA

    else
       echo "MDS detected"
       echo ""

       DESIRED_CMA="$1"

       shopt -s nocasematch
       if [[ $DESIRED_CMA == "all" ]]; then
           for CMA in $($MDSVERUTIL AllCMAs); do
              echo ""
              echo "processing $CMA"
              mdsenv $CMA
              bundle_loop $CMA
              echo "Completed $CMA"
           done
        else
            echo ""
            echo "processing $DESIRED_CMA"
            mdsenv $DESIRED_CMA
            bundle_loop $DESIRED_CMA
            echo "Completed $DESIRED_CMA"
        fi
    # reset mdsenv
    mdsenv
    fi

    echo ""
    echo "All logs and command output files are stored in ${OUTPUT_DIR}"

    if [ "$SEND_EMAILS" = true ]; then
        echo "Sending notification emails"
        send_email
    fi

}

function list_cmas {
    echo "CMA names:"
    echo ""
    for CMA in $($MDSVERUTIL AllCMAs); do
        echo $CMA
    done
}

function email_log_message {

    #Display on command line
    echo -e "${1}"
    #Append to $TEMP_MAIL_FILE which will be sent to users
    echo -e $1 >> $TEMP_MAIL_FILE

}

function send_email {

    rm -f $TEMP_MAIL_FILE
    touch $TEMP_MAIL_FILE

    ### Start building the temp file we will use for email notifications
    email_log_message "$MAIL_FROM\n$MAIL_TO\n$(hostname) Log File Compression and Upload Notification ${DATETIME}\n"
    email_log_message "All log files can be found on $(hostname) in ${OUTPUT_DIR}\n\n"

    if (( ${#UPLOAD_ERRORS[@]} )); then
        email_log_message "===== UPLOAD ERRORS =====\n"
        for entry in "${UPLOAD_ERRORS[@]}"
        do
            ### Add each upload error to the body of the email
            email_log_message "$entry\n"
        done
    else
        email_log_message "No upload errors during run of $SN at ${DATETIME}"
    fi

    if (( ${#SUCCESSFUL_UPLOADS[@]} )); then
        email_log_message "\n===== SUCCESSFUL UPLOADS =====\n"
        for entry in "${SUCCESSFUL_UPLOADS[@]}"
        do
            ### Add each successful upload to the body of the email
            email_log_message "$entry\n"
        done
    else
        email_log_message "No archive upload attempts during run of $SN at ${DATETIME}"
    fi

    $MDS_FWDIR/bin/sendmail -t $MAIL_SERVER_IP -m $TEMP_MAIL_FILE

    #Remove temporary files
    rm -f $TEMP_MAIL_FILE
    rm -f $TEMP_UPLOAD_LOG_FILE

}

## END OF FUNCTION DECLARATIONS ##

DEMO=""

if [[ $1 != "-l" ]] && [[ -z $1 || -z $2 || $1 = "-h" || $1 = "--help" ]]; then
    echo ""
    echo "tar and gzips Checkpoint log files and related log pointer files."
    echo "Can either operate automatically for all logs older than $LOG_AGE days"
    echo "or can operate on a specific log file."
    echo "For automatic operation, will detect if on an MDS and will iterate"
    echo "over all CMAs."
    echo ""
    echo "Usage Guide:"
    echo "Specify the CMA name or all to run through all CMA's in a loop"
    echo " $SN -a <CMA_NAME or all> = auto bundle (bundle all logs older than $LOG_AGE days, upload archives older than $ARCHIVE_AGE days)"
    echo " $SN -t <CMA_NAME or all> = test mode (just echo commands used for auto bundle)"
    echo " $SN -l = list all CMA names on this server"
    echo " $SN <logname> = bundle <logname>"
    echo ""
    exit
fi

case $1 in
-t)
    DEMO="echo"
    DEMO_SUFFIX="yes"
    autobundle $2
    ;;
-a)
    DEMO=""
    DEMO_SUFFIX=""
    autobundle $2
    ;;
-l)
    list_cmas
    ;;
*)
    do_bundle $1
    ;;
esac

echo ""