# chkp_compress_and_upload_logs_aws_s3
Used to collect archive logs on a Check Point MDS or MLM log server, and upload to AWS S3 after a certain aging period has passed. Verifies remote file MD5 matches local file, and deletes local copy automatically

Requires an S3 bucket with a user configured for programmatic access

Script file is stored in /var/log to prevent any issues with upgrades not carrying files in user directories

AWS Keys / S3 Bucket info is stored in a separate file (aws_keys), a blank template is created on first run in the same directory as the script

Script is capable of emailing notifications (requires unauthenticated relay permissions on the SMTP server) - in the script set SEND_EMAILS=true

SMTP server info is stored in a separate file (smtp_settings), a blank template is created on first run in the same directory as the script once email is enabled

Run manually, or setup a cron job to run the script nightly for automated cleanup

Script will put diagnostic data in the following default directory:
/var/log/tmp/compress_and_upload_output



## Instructions 

### Script setup
1. ssh into a Check Point log server as admin
1. enter expert mode
1. copy file [chkp_compress_and_upload_logs_aws_s3.sh](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/backup_scripts/chkp_compress_and_upload_logs_aws_s3.sh) to /home/admin/ on log server
   ```
   curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/backup_scripts/chkp_compress_and_upload_logs_aws_s3.sh > /var/log/chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. chmod the script to be executable
   ```
   chmod u+x /var/log/chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. Run the script
   ```
   /var/log/./chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. Additional info can be found by running the script with no arguments, -h or --help
