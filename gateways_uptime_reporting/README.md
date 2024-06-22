# Report on Gateways uptime #

Script to report gateways uptime, save output to CSV

Supports MDS only currently

### $${\color{red}This script is not an official Check Point Software Technologies script}$$
### Use of this script is at users own risk
### No support will be provided for this script by Check Point Software Technologies

#### Download and configure the script to run on your management server
1. Download the script [gateway_uptime_export_csv.bash](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/gateways_uptime_reporting/gateway_uptime_export_csv.bash) in expert mode:
    ```
    curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/gateways_uptime_reporting/gateway_uptime_export_csv.bash > /var/log/gateway_uptime_export_csv.bash
    ```
1. Run the script manually
    ```
    bash /var/log/gateway_uptime_export_csv.bash
    ```


