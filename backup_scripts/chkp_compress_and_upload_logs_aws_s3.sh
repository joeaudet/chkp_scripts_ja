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
# 2020-09-30 JA - Added in functionality to list all CMA names
#               - Added in ability to specify individual CMA name or loop all CMA names
#               - Added command to test function to add output to output file per CMA for review before running
#               - Updated S3 upload mechanism to create the following directory structure for uploads: CMA/YEAR/MONTH/FILES
# 2020-10-01 JA - Added ANSI color codes for some output messages
#               - Moved AWS BUCKET and keys to separate file that is imported so not overwritten on updates
#               - Check if $KEYS_FILE exists, if not create it with empty values and alert user to fill in those values
#
##


# Ansi color code variables
ANSI_RED="\e[0;91m"
ANSI_RESET="\e[0m"

SN=${0##*/}
KEYS_FILE="aws_keys"

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

#As of 2020-10-01 - not able to figure out correct formatting
#CACERT not used yet
#CACERT=/home/admin/awss3_cacert.pem

# set this to the number of days that you wish to keep logs unbundled for
LOG_AGE=30

# this one is the number of days to upload and delete archive bundles after (set to 0 to disable)
ARCHIVE_AGE=90

## FUNCTIONS ###
function upload_to_aws_s3 {
file=$1
#AWSPATH format - CMA/YEAR/MONTH
AWSPATH="${2}/${3}/${4}"
ECHO_SUFFIX=$5
FILENAME=$(echo $file | sed 's/\.\///');\
DATEVALUE=`date -R`
RESOURCE="/${BUCKET}/${AWSPATH}/${file}"
CONTENTTYPE="application/x-compressed-tar"
STRINGTOSIGN="PUT\n\n${CONTENTTYPE}\n${DATEVALUE}\n${RESOURCE}"
MD5SUM=$($MDS_CPDIR/bin/cpopenssl md5 -binary "$file" | base64)
SIGNATURE=`echo -en ${STRINGTOSIGN} | $MDS_CPDIR/bin/cpopenssl sha1 -hmac ${S3SECRET} -binary | base64`
    if [[ $DEMO = "echo" ]]; then
        echo "curl_cli -s -k -o /dev/null -D - -X PUT -T "${FILENAME}" \
        -H "Host: ${BUCKET}.s3.amazonaws.com" \
        -H "Date: ${DATEVALUE}" \
        -H "Content-Type: ${CONTENTTYPE}" \
        -H "Content-MD5=$MD5SUM" \
        -H "Authorization: AWS ${S3KEY}:${SIGNATURE}" \
        https://${BUCKET}.s3.amazonaws.com/${AWSPATH}/${FILENAME}"  >> $ECHO_SUFFIX;
    else
        curl_cli -s -k -o /dev/null -D - -X PUT -T "${FILENAME}" \
        -H "Host: ${BUCKET}.s3.amazonaws.com" \
        -H "Date: ${DATEVALUE}" \
        -H "Content-Type: ${CONTENTTYPE}" \
        -H "Content-MD5=$MD5SUM" \
        -H "Authorization: AWS ${S3KEY}:${SIGNATURE}" \
        https://${BUCKET}.s3.amazonaws.com/${AWSPATH}/${FILENAME}
    fi
}

# Bundles log and pointers for logfile passed in as sole parameter
function do_bundle {
    INLOG=$1
    CMA=$2
    ECHO_SUFFIX="$3"
    LOGDATE=""
    LOGDATE=$(echo $INLOG | sed 's/\.\///' | sed 's/_[0-9]*\.[a-z]*//');\
    LOGFILENAME=$(echo $INLOG | sed 's/\.\///');\
    LOGFILEWITHOUTEXT=$(echo $LOGFILENAME | cut -f 1 -d '.')
    ARCHIVEFILENAME="${LOGFILENAME}_${CMA}.tar.gz"

    if [ -e ${LOGFILENAME}.tar.gz ]; then
            echo "${LOGFILENAME}.tar.gz already exists, skipping"
            continue
    fi

    #fix timestamp
    MAKEDATE=$(echo $LOGFILEWITHOUTEXT | cut -f 1,2,3 -d '-' | cut -f 1 -d '_'  | sed 's/\-//g')


    if [[ $DEMO = "echo" ]]; then
        echo "tar czvf $ARCHIVEFILENAME --remove-files ${LOGFILEWITHOUTEXT}*" >> $ECHO_SUFFIX;
        echo "touch -t ${MAKEDATE}"2359" $ARCHIVEFILENAME" >> $ECHO_SUFFIX
    else
        tar czvf $ARCHIVEFILENAME --remove-files ${LOGFILEWITHOUTEXT}* ;\
        touch -t ${MAKEDATE}"2359" $ARCHIVEFILENAME
    fi
}

# For autobundle (and test) finds all logfiles of interest and calls do_bundle
#  on them.
function bundle_loop {
   cd $FWDIR/log
   CMA=$1
   LOGLIST=`find . -mtime +$LOG_AGE -name "*.log"`
   ARCHIVELIST=`find . -mtime +$ARCHIVE_AGE -name "*.gz"`


   if [[ $DEMO_SUFFIX == "yes" ]]; then
       #Output file for DEMO option to echo commands to for review
       COMMAND_OUTPUT_DIR="/var/log/tmp/compress_and_upload_output"
       #Check if directory exists, if not create it
       [ ! -d $COMMAND_OUTPUT_DIR ] && mkdir -p "$COMMAND_OUTPUT_DIR"
       COMMAND_OUTPUT_FILE="${COMMAND_OUTPUT_DIR}/${CMA}_compress_upload_output.txt"
       rm -f $COMMAND_OUTPUT_FILE
       echo "cd $(pwd)" >> $COMMAND_OUTPUT_FILE
   fi

   if [ "$LOGLIST" != "" ]; then
        for LOG in $LOGLIST; do
            do_bundle $LOG $CMA $COMMAND_OUTPUT_FILE
        done
    else
        echo "No logs to archive"
    fi

   if [ "$ARCHIVELIST" != "" ]; then
        for ARCHIVE in $ARCHIVELIST; do
            ARCHIVE=$(echo $ARCHIVE | sed 's/\.\///');\
                        echo "Archive: $ARCHIVE"
            YEAR=$(echo $ARCHIVE | cut -f 1 -d '-')
            MONTH=$(echo $ARCHIVE | cut -f 2 -d '-')
            upload_to_aws_s3 $ARCHIVE $CMA $YEAR $MONTH $COMMAND_OUTPUT_FILE
        done
    else
        echo "No matching archives to upload"
    fi

#Still working out upload validation logic to confirm successful upload before deleting files automatically on 2020SEP30 - JA
#    if [ "$ARCHIVE_AGE" -gt 0 ]; then
#        DELETELIST=`find . -mtime +$ARCHIVE_AGE -name "*.gz"`
#        if [[ $DEMO = "echo" ]]; then
#            for BUNDLE in $DELETELIST; do
#                BUNDLE=$(echo $BUNDLE | sed 's/\.\///');\
#                echo "/bin/rm -v $BUNDLE" >> $COMMAND_OUTPUT_FILE
#            done
#        else
#            for BUNDLE in $DELETELIST; do
#                           BUNDLE=$(echo $BUNDLE | sed 's/\.\///');\
#                /bin/rm -v $BUNDLE
#            done
#        fi
#    fi
}

# Detects if on Smartcenter or Provider-1 and runs bundle_loop for each
# CMA or just once for Smartcenter
function autobundle {
    if [ -r /etc/profile.d/CP.sh ]; then
       . /etc/profile.d/CP.sh
    else
        echo "Could not source /etc/profile.d/CP.sh"
        exit
    fi

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
}

function list_cmas {
    echo "CMA names:"
    echo ""
    for CMA in $($MDSVERUTIL AllCMAs); do
        echo $CMA
    done
}

## END OF FUNCTION DECLARATIONS ##

DEMO=""

if [[ $1 != "-l" ]] && [[ -z $1 || -z $2 || $1 = "-h" || $1 = "--help" ]]; then
    SN=${0##*/}
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