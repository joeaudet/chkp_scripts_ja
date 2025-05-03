# Report on Gateways uptime #

Script to report gateways Name, IP, Mgmt MAC, Platform, Model, and Serial - save output to CSV

Supports SMS only currently
Limited to 500 objects currently

>[!WARNING]
> ### This script is not an official Check Point Software Technologies script. Use of this script is at users own risk. No support will be provided for this script by Check Point Software Technologies

#### Download and configure the script to run on your management server
1. Download the script [find_gateways_mgmt_mac_address.bash](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/get_gateways_mgmt_info/find_gateways_mgmt_mac_address.bash) in expert mode:
    ```
    curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/get_gateways_mgmt_info/find_gateways_mgmt_mac_address.bash > /var/log/tmp/find_gateways_mgmt_mac_address.bash
    ```
1. Run the script manually
    ```
    bash /var/log/tmp/find_gateways_mgmt_mac_address.bash
    ```


