#!/bin/bash

#AWS S3 user defined variables
bucket=xxx
s3Key=xxx
s3Secret=xxx
awspath=xxx

function upload_to_aws_s3 {
file=$1
awspath=$2
dateValue=`date -R`
resource="/${bucket}/${awspath}/${file}"
contentType="application/x-compressed-tar"
stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
signature=`echo -en ${stringToSign} | $MDS_CPDIR/bin/cpopenssl sha1 -hmac ${s3Secret} -binary | base64`
curl_cli -k -X PUT -T "${file}" \
  -H "Host: ${bucket}.s3.amazonaws.com" \
  -H "Date: ${dateValue}" \
  -H "Content-Type: ${contentType}" \
  -H "Authorization: AWS ${s3Key}:${signature}" \
  https://${bucket}.s3.amazonaws.com/${awspath}/${file}
}

if [[ -z $1 || $1 = "-h" || $1 = "--help" ]]; then
        SN=${0##*/}
        echo ""
        echo "You must specify a filename to upload"
        echo ""
        exit
fi

case $1 in

*)
    echo $1
    upload_to_aws_s3 $1 $awspath
    ;;
esac
