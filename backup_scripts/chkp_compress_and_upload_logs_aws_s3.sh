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
# 2020-08-20 JA - Add in AWS S3 storage upload capabilities
# 2020-08-27 JA - Modified do_bundle to put each log file in its own archive 
#                 to ensure no issues with 2GB file creation limit
#               - Changed autobundled to use $($MDSVERUTIL AllCMAs) instead of creating an array of CMA's
#
##

#AWS S3 user defined variables
bucket=xxx
s3Key=xxx
s3Secret=xxx
#CACERT not used yet
#CACERT=/home/admin/awss3_cacert.pem

# set this to the number of days that you wish to keep logs unbundled for
LOG_AGE=30

# this one is the number of days to upload and delete archive bundles after (set to 0 to disable)
ARCHIVE_AGE=90

## FUNCTIONS ###

#Upload file to storage provider
function upload_to_aws_s3 {
file=$1
awspath=$2
FILENAME=$(echo $file | sed 's/\.\///');\
dateValue=`date -R`
resource="/${bucket}/${awspath}/${file}"
contentType="application/x-compressed-tar"
stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
signature=`echo -en ${stringToSign} | $MDS_CPDIR/bin/cpopenssl sha1 -hmac ${s3Secret} -binary | base64`
$DEMO curl_cli -k -X PUT -T "${FILENAME}" \
  -H "Host: ${bucket}.s3.amazonaws.com" \
  -H "Date: ${dateValue}" \
  -H "Content-Type: ${contentType}" \
  -H "Authorization: AWS ${s3Key}:${signature}" \
  https://${bucket}.s3.amazonaws.com/${awspath}/${FILENAME}
}

# Bundles log and pointers for logfile passed in as sole parameter
function do_bundle {
        INLOG=$1
        LOGDATE=$(echo $INLOG | sed 's/\.\///' | sed 's/_[0-9]*\.[a-z]*//');\
		LOGFILENAME=$(echo $INLOG | sed 's/\.\///');\

        if [ -e ${LOGFILENAME}.tar.gz ]; then
                echo "${LOGFILENAME}.tar.gz already exists, skipping"
                continue
        fi
        $DEMO tar czvf ${LOGFILENAME}.tar --remove-files ${LOGFILENAME}* ;\

        #fix timestamp
        MAKEDATE=$(echo $LOGDATE | sed 's/\-//g')
        $DEMO touch -t ${MAKEDATE}"2359" ${LOGFILENAME}.tar.gz
}


# For autobundle (and test) finds all logfiles of interest and calls do_bundle
#  on them.
function bundle_loop {
   cd $FWDIR/log
   LOGLIST=`find . -mtime +$LOG_AGE -name "*.log"`
   ARCHIVELIST=`find . -mtime +$ARCHIVE_AGE -name "*.gz"`

   if [ "$LOGLIST" != "" ]; then
        for LOG in $LOGLIST; do
            do_bundle $LOG
        done
    else
        echo "No logs to archive"
    fi

   if [ "$ARCHIVELIST" != "" ]; then
        for ARCHIVE in $ARCHIVELIST; do
            upload_to_aws_s3 $ARCHIVE $1
        done
    else
        echo "No matching archives to upload"
    fi

    if [ "$ARCHIVE_AGE" -gt 0 ]; then
        DELETELIST=`find . -mtime +$ARCHIVE_AGE -name "*.gz"`
        for BUNDLE in $DELETELIST; do
            $DEMO /bin/rm -v $BUNDLE
        done
    fi
}

# Detects if on Smartcenter or Provider-1 and runs bundle_loop for each
#  CMA or just once for Smartcenter
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

       bundle_loop

    else
       echo "MDS detected"
       echo ""

       for CMA in $($MDSVERUTIL AllCMAs); do
          echo ""
          echo "processing $CMA..."
          mdsenv $CMA

          bundle_loop $CMA

          echo "Completed $CMA"
       done

    # reset mdsenv
    mdsenv
    fi
}

## END OF FUNCTION DECLARATIONS ##

DEMO=""

if [[ -z $1 || -n $2 || $1 = "-h" || $1 = "--help" ]]; then
    SN=${0##*/}
    echo ""
    echo "tar and gzips Checkpoint log files and related log pointer files."
    echo "Can either operate automatically for all logs older than $LOG_AGE days"
    echo "or can operate on a specific log file."
    echo "For automatic operation, will detect if on an MDS and will iterate"
    echo "over all CMAs."
    echo ""
    echo "Usage Guide:"
    echo " $SN -a = auto bundle (bundle all logs older than $LOG_AGE days, upload archives older than $ARCHIVE_AGE days)"
    echo " $SN -t = test mode (just echo commands used for auto bundle)"
    echo " $SN <logname> = bundle <logname>"
    echo ""
    exit
fi

case $1 in
-t)
    DEMO="echo"
    autobundle
    ;;
-a)
    DEMO=""
    autobundle
    ;;
*)
    do_bundle $1
    ;;
esac

echo ""