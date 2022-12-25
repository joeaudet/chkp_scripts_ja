# Find expiring VPN certificates #

Script to find and report on VPN certificates that are expiring and create a CSV output  
Supports SMS / MDS - operates accordingly based on type of mgmt server
Optional email notification can be enabled

Default look ahead is 60 days. This can be changed within the script by changing the value of: AMOUNT_OF_DAYS

### This script is not an official Check Point Software Technologies script
### Use of this script is at users own risk
### No support will be provided for this script by Check Point Software Technologies

#### Download and configure the script to run on your management server
1. Download the script [find_expiring_vpn_certs_sms.bash](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/expiring_vpn_certs_reporting/find_expiring_vpn_certs.bash) in expert mode:
    ```
    curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/expiring_vpn_certs_reporting/find_expiring_vpn_certs.bash > /var/log/find_expiring_vpn_certs.bash
    ```
1. Run the script manually
    ```
    bash /var/log/find_expiring_vpn_certs.bash
    ```

#### Create a cron job to run the script daily
1. In CLISH  
    ```
    add cron job Check_VPN_Cert_Exp command "bash /var/log/find_expiring_vpn_certs.bash" recurrence daily time 0:01  
    save config
    ```

#### Enable email notifications
1. PRE_REQUISITE: Make sure your email server is setup to receive unauthenticated email from your mgmt server
2. Edit the smtp_settings file located in the same directory as the script - /var/log/smtp_settings - put in your information. Only one destination email allowed, use a distro group
    ```
    SEND_EMAILS=false; <-Change this to true, default is false
    MAIL_TO=""  
    MAIL_FROM=""  
    MAIL_SERVER_IP=""  
    ```
