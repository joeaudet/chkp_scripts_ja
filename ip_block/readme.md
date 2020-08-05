# ip__block
Unofficial customization of [sk103154](https://supportcenter.checkpoint.com/supportcenter/portal?eventSubmit_doGoviewsolutiondetails=&solutionid=sk103154) scripts used for automated IPv4 blocking

## Instructions 
- Download the scripts to your management server and deploy following the instructions in [sk103154](https://supportcenter.checkpoint.com/supportcenter/portal?eventSubmit_doGoviewsolutiondetails=&solutionid=sk103154)
	***This will overwrite the file - make sure you back up any changes***
	```
	curl_cli -k https://raw.githubusercontent.com/joeaudet/chkp_scripts_ja/master/ip_block/ip_block.sh > ip_block.sh
	```