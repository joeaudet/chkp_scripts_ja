# ckpt_collect_log_file_sizes
Used to collect archive logs on a Check Point MDS or MLM log server, and upload to AWS S3 after a certain aging period has passed

## Instructions 

### Script setup
1. ssh into a Check Point log server as admin
1. enter expert mode
1. copy file [chkp_compress_and_upload_logs_aws_s3.sh](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/backup_scripts/chkp_compress_and_upload_logs_aws_s3.sh) to /home/admin/ on log server
   ```
   curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/backup_scripts/chkp_compress_and_upload_logs_aws_s3.sh > /home/admin/chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. chmod the script to be executable
   ```
   chmod u+x /home/admin/chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. Run the script
   ```
   /home/admin/./chkp_compress_and_upload_logs_aws_s3.sh
   ```
1. Additional instructions coming
