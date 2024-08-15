# Export access-layers to CSV for reporting #

Script to export a single policy or all policies to CSV including hit count information to allow users to find unused rules

Supports SMS currently (MDS coming)

>[!WARNING]
> ### This script is not an official Check Point Software Technologies script. Use of this script is at users own risk. No support will be provided for this script by Check Point Software Technologies

#### Download and configure the script to run on your management server
1. Download the script [chkp_hit_count_to_csv_reporting.py](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/hit_count_reporting/chkp_hit_count_to_csv_reporting.py) in expert mode:
    ```
    curl_cli -k -O https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/hit_count_reporting/chkp_hit_count_to_csv_reporting.py
    ```
1. Run the script manually
    ```
    python3 chkp_hit_count_to_csv_reporting.py
    ```

#### MDS Test version
1. Download the script [chkp_hit_count_to_csv_reporting_MDS_v2.py](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/hit_count_reporting/chkp_hit_count_to_csv_reporting_MDS_v2.py) in expert mode:
    ```
    curl_cli -k -O https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/hit_count_reporting/chkp_hit_count_to_csv_reporting_MDS_v2.py
    ```
1. Run the script manually
    ```
    python3 chkp_hit_count_to_csv_reporting_MDS_v2.py
    ```