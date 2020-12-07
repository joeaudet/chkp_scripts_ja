# Misc cross domain search scripts #

### cross_domain_ip_search.ps1
Written to allow for searching for existince of a host in all domains on an MDS server

#### On the workstation with Powershell (Only tested on Windows 10)
1. Download the script [cross_domain_ip_search.ps1](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/cross_domain_search/cross_domain_ip_search.ps1) to workstation in command prompt window:
	```
	curl https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/cross_domain_search/cross_domain_ip_search.ps1 > cross_domain_ip_search.ps1
	```
1. Edit the script in an editor to change the API_USERNAME and API_PASSWORD to read only credentials created for this search function (will be updated with API KEY when available)
1. Run the script, enter search IP and MDS IP when prompted
	```
	./cross_domain_ip_search.ps1
	```

- - - -

### cross_domain_where-used.sh
Written to allow for retrieving where-used data from all domains on an MDS server

#### On the MDS server
1. SSH into the MDS server
1. From expert mode download the script [cross_domain_where-used.sh](https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/cross_domain_search/cross_domain_where-used.sh):
	```
	curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/cross_domain_search/cross_domain_where-used.sh > cross_domain_where-used.sh
	```
1. Mark script as executable
	```
	chmod u+x cross_domain_where-used.sh
	```
1. Run the script, enter search IP and MDS IP when prompted
	```
	./cross_domain_where-used.sh <objectname>
	```
