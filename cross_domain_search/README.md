# cross_domain_ip_search.ps1
Written to allow for searching for existince of a host in all domains on an MDS server

### On the workstation with Powershell (Only tested on Windows 10)
1. Download the script [cross_domain_ip_search.ps1](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/cross_domain_search/cross_domain_ip_search.ps1) to workstation
1. Edit the script to change the API_USERNAME and API_PASSWORD to read only credentials created for this search function (will be updated with API KEY when available)
1. Run the script, enter search IP and MDS IP when prompted
	```
	./cross_domain_ip_search.ps1
	```
