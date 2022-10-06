# Find expiring VPN certificates #

### find_expiring_vpn_certs_sms.bash
Written to allow for searching for VPN certificates that will be expiring within a certain amount of days from day script is run  
Script will create a CSV output file with all certificates, and can be configured to email

### This script is not an official Check Point Software Technologies script
### Use of this script is at users own risk
### No support will be provided for this script by Check Point Software Technologies

#### Download and configure the script to run on your management server
1. Download the script [find_expiring_vpn_certs_sms.bash](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/expiring_vpn_certs_reporting/find_expiring_vpn_certs_sms.bash) in expert mode:
    ```
    curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/expiring_vpn_certs_reporting/find_expiring_vpn_certs_sms.bash > /var/log/find_expiring_vpn_certs_sms.bash
    ```
1. Run the script manually
    ```
    bash /var/log/find_expiring_vpn_certs_sms.bash
    ```

#### Create a cron job to run the script daily
1. In CLISH  
    ```
    add cron job Check_VPN_Cert_Exp command "bash /var/log/find_expiring_vpn_certs_sms.bash" recurrence daily time 0:01  
    save config
    ```

#### Enable email notifications
1. Change this variable within the script to true (default is false)
    ```
    SEND_EMAILS=true;
    ```
2. Run the script once
    ```
    bash /var/log/find_expiring_vpn_certs_sms.bash
    ```
3. Edit the smtp_settings file located in the same directory as the script - /var/log/smtp_settings - put in your information. Only one destination email allowed, use a distro group
    ```
    MAIL_TO=""  
    MAIL_FROM=""  
    MAIL_SERVER_IP=""  
    ```
