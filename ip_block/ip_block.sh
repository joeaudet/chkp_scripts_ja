#!/bin/bash

SCRIPT_NAME=$0
OPERATION="$1" # on, off, etc
CPD_SCHED_CONFIG="$CPDIR/bin/cpd_sched_config"
CPD_SCHED_PROG_NAME="ip_block"
CPD_SCHED_TIMEOUT=1200 #cpd_sched_config interval in seconds
SAMP_RULE_TIMEOUT=3600 #duration in seconds for each samp rule (should be gt CPD_SCHED_TIMEOUT)
BUFFER=60 #window buffer 
CACHE_FILE_OLD="$FWDIR/database/cache.bip" #cache file
BYPASS_LIST_FILE="$FWDIR/database/block_ip_bypass_feed_gw.txt" #bypass feed file
CPDIAG_LOG="$FWDIR/database/block_ip_stat.txt" #script status 
URL_FILE="$FWDIR/database/block_ip_feeds_gw.txt" #gw url feed file
CACHE_FILE_NEW="$FWDIR/database/cache_tmp.bip" #cache tmp file
CACHE_FOLDER="$FWDIR/database/"
LOG_FILE="$FWDIR/log/ip_block.log"
SAMP_COMMENT="threatcloud_ip_block"
SAMP_COMMENT_BYPASS="threatcloud_ip_block_bypass"
NEED_UPDATE=0 #does an update is needed? (in case the url was updated/ or timeout has occure)

declare -a CACHE_URL_OLD
declare -a CACHE_LAST_UPDATE_OLD
declare -a CACHE_TIMEOUT_OLD

IS_FW_MODULE=$($CPDIR/bin/cpprod_util FwIsFirewallModule)

MY_PROXY=$(clish -c 'show proxy address'|awk '{print $2}'| grep  '\.')
MY_PROXY_PORT=$(clish -c 'show proxy port'|awk '{print $2}'| grep -E '[0-9]+')
if [ ! -z "$MY_PROXY" ]; then
	HTTPS_PROXY="$MY_PROXY:$MY_PROXY_PORT"
fi

function log_line {
	# add timestamp to all log lines
	message=$1
	local_log_file=$2	
	echo "$(date) $message" >> $local_log_file
}

function read_cache {
	log_line "read_cache from file $CACHE_FILE_OLD" $LOG_FILE
	touch $CACHE_FILE_OLD
	COUNTER=0
	while IFS='#' read -ra lastupdate || [[ -n "$lastupdate" ]]; do		
		CACHE_URL_OLD[$COUNTER]=${lastupdate[0]}
		CACHE_LAST_UPDATE_OLD[$COUNTER]=${lastupdate[1]}
		CACHE_TIMEOUT_OLD[$COUNTER]=${lastupdate[2]}
		let COUNTER=COUNTER+1 
	done < "$CACHE_FILE_OLD"
}

function convert {
     while read ip; do
        if [ ! -z "$ip" ] && [ ${ip:0:1} != "#" ]
        then
			echo "add -a d -l r -t $SAMP_RULE_TIMEOUT -c $SAMP_COMMENT quota service any source range:$ip pkt-rate 0"
        fi
     done 
}

function end_samp {
	if [ "$NEED_UPDATE" -eq "1" ] 
	then
		echo "add -t $SAMP_RULE_TIMEOUT quota flush true" | fw samp batch
	fi
}

function end_now {
	echo "add -t $SAMP_RULE_TIMEOUT quota flush true" | fw samp batch
}

function update_cache {	
	if [ "$NEED_UPDATE" -eq "1" ] 
	then
		mv $CACHE_FILE_NEW $CACHE_FILE_OLD
	else
		rm $CACHE_FILE_NEW
	fi
}

function update_one_url {	
	url=$1
	log_line "updating $url" $LOG_FILE
	
	if [ -z "$HTTPS_PROXY" ]
	then
		log_line "Not using proxy" $LOG_FILE
		LAST_UPDATE=$(curl_cli --head -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url | grep 'Last-Modified'|  tr -d ' ' | tr -d ',' | dos2unix)
	else
		log_line "Using proxy $HTTPS_PROXY" $LOG_FILE
		LAST_UPDATE=$(curl_cli --head -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url --proxy $HTTPS_PROXY | grep 'Last-Modified'|  tr -d ' ' | tr -d ',' | dos2unix)
	fi
	log_line "LAST_UPDATE = $LAST_UPDATE" $LOG_FILE

	internal_counter=0
	old_last_update=""
	old_cpd_sched_timeout_sec=0
	new_timeout_sec=$(date +%s)
	cache_file_name=$(echo $url | sed 's/[\"\.:\/-]//g')
	cache_file_name=$CACHE_FOLDER$cache_file_name
	
	
	#get old LAST_UPDATE from cahce file
	for old_url in ${CACHE_URL_OLD[@]}; do
		case $old_url in 
			$url) old_last_update=${CACHE_LAST_UPDATE_OLD[$internal_counter]};old_cpd_sched_timeout_sec=${CACHE_TIMEOUT_OLD[$internal_counter]};	
		esac
		let internal_counter=internal_counter+1 
	done
	
	last_update_delta=$((new_timeout_sec - old_cpd_sched_timeout_sec + BUFFER))
	samp_delta=$((SAMP_RULE_TIMEOUT - CPD_SCHED_TIMEOUT)) 
	log_line "last_update new = $LAST_UPDATE" $LOG_FILE
	log_line "last_update old = $old_last_update" $LOG_FILE
	log_line "old_timeout = $old_cpd_sched_timeout_sec" $LOG_FILE
	log_line "new_timeout_sec = $new_timeout_sec" $LOG_FILE
	log_line "file name = $cache_file_name" $LOG_FILE
	log_line "last_update_delta = $last_update_delta" $LOG_FILE
	log_line "samp_rule_timeout = $SAMP_RULE_TIMEOUT" $LOG_FILE
	log_line "samp_delta = $samp_delta" $LOG_FILE
	
	#verify if the last_update was changed (if this feed should be update)
	if [ "$LAST_UPDATE" = "$old_last_update" ] 
	then
		log_line "$url: feed is up to date" $LOG_FILE
		#timeout is getting by
		if [ "$last_update_delta" -gt "$samp_delta" ]
		then
			log_line "updating $url from cache" $LOG_FILE
			NEED_UPDATE=1
			cat $cache_file_name | grep -vE '^$'| fw samp batch
		fi
	else
		log_line "$url: not up to date. Updating.." $LOG_FILE
		NEED_UPDATE=1
		if [ -z "$HTTPS_PROXY" ]
		then
			curl_cli -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url | dos2unix | grep -vE '^$'| convert > $cache_file_name
		else
			curl_cli -s --cacert $CPDIR/conf/ca-bundle.crt --retry 10 --retry-delay 60 $url --proxy $HTTPS_PROXY | dos2unix | grep -vE '^$'| convert > $cache_file_name
		fi
		insert_samp_anw=$(cat $cache_file_name | grep -vE '^$'| fw samp batch)
		if echo $insert_samp_anw | grep -v "ucceeded"; then
			echo "Error in feed: $url"
			log_line "error in feed: $url" $LOG_FILE
		fi
	fi
	
	#updating tmp cahce file
	echo "$url#$LAST_UPDATE#$new_timeout_sec" >> $CACHE_FILE_NEW
	log_line "Done update cache: $CACHE_FILE_NEW, content:$url#$LAST_UPDATE#$new_timeout_sec" $LOG_FILE
}

function update_feeds {
	log_line "update_feeds" $LOG_FILE
	while IFS='' read -r url || [[ -n "$url" ]]; do
		if [ ! -z "$url" ] && [ ${url:0:1} != "#" ]
        then
			update_one_url $url
		fi
		
	done < "$URL_FILE"
}

function remove_existing_sam_rules {
	fw samp get | awk -v samp_comment_awk="comment="$SAMP_COMMENT '$0 ~ samp_comment_awk {sub("uid=","",$2);print "del "$2}' | fw samp batch 1>/dev/null 2>&1
	fw samp add -t 2 quota flush true 1>/dev/null 2>&1
	rm $CACHE_FILE_OLD
}
	
function remove_bypass_sam_rules {
	fw samp get | awk -v samp_comment_awk="comment="$SAMP_COMMENT_BYPASS '$0 ~ samp_comment_awk {sub("uid=","",$2);print "del "$2}' | fw samp batch 1>/dev/null 2>&1
	fw samp add -t 2 quota flush true 1>/dev/null 2>&1
	rm $CACHE_FILE_OLD
}

function bypass_list {
     while read ip; do
        if [ ! -z "$ip" ] && [ ${ip:0:1} != "#" ]
        then
			echo "add -a b -c $SAMP_COMMENT_BYPASS quota service any source range:$ip"
        fi
     done
}

function run_action {
	log_line "run_action" $LOG_FILE
	
	read_cache
	log_line "done read_cache" $LOG_FILE

	update_feeds
	log_line "done update_feeds" $LOG_FILE

	update_cache
	log_line "done update_cache" $LOG_FILE

	end_samp
	log_line "done end_samp" $LOG_FILE
}


# Run only on GAIA gateways
if [[ "$IS_FW_MODULE" -eq 1 && -f /etc/appliance_config.xml ]]; then
	echo "$(date) ==== Starting to run $0 $@ ====" > $LOG_FILE
	case "$OPERATION" in
		on)
		test_url=$(cat $URL_FILE| grep -vE '#'| grep -vE '^$'| head -n 1)
		url_list=$(cat $URL_FILE | grep -vE '#' | grep -vE '^$'| awk '{printf $0", "}' )
		
		echo "STATUS:ON" > $CPDIAG_LOG
		
		$CPD_SCHED_CONFIG add $CPD_SCHED_PROG_NAME -c "$FWDIR/bin/ip_block.sh run" -e $CPD_SCHED_TIMEOUT -r -s 
		echo "$CPD_SCHED_PROG_NAME: Malicious IP blocking mechanism is ON"
		
		#verify curl is working and the internet access is avaliable
		if [ -z "$HTTPS_PROXY" ]
		then
			
			test_curl=$(curl_cli --head -s --cacert $CPDIR/conf/ca-bundle.crt --retry 2 --retry-delay 20 $test_url | grep HTTP)	
		else
			test_curl=$(curl_cli --head -s --cacert $CPDIR/conf/ca-bundle.crt $test_url --proxy $HTTPS_PROXY | grep HTTP)
		fi
		
		if [ -z "$test_curl" ]
		then 
			echo "Warning, cannot connect to $test_url"
		fi
		log_line "done testing http connection" $LOG_FILE
		
		;;
		
		run)
		run_action
		;;
		
		off)		
		echo "STATUS:OFF" > $CPDIAG_LOG
		
		$CPD_SCHED_CONFIG delete $CPD_SCHED_PROG_NAME -r 
		remove_existing_sam_rules
		echo "$CPD_SCHED_PROG_NAME: Malicious IP blocking mechanism is OFF"
		;;

		allow)
		log_line "adding bypass rules" $LOG_FILE
		cat $BYPASS_LIST_FILE | grep -vE '^$'| bypass_list | fw samp batch
		end_now
		log_line "done end_samp" $LOG_FILE
		echo "$CPD_SCHED_PROG_NAME: Malicious IP blocking mechanism updated bypass list"
		;;
		
		delete_bypass)
		log_line "clear bypass rules" $LOG_FILE
		remove_bypass_sam_rules
		end_samp
		log_line "done end_samp" $LOG_FILE
		echo "$CPD_SCHED_PROG_NAME: Malicious IP blocking mechanism cleared bypass list"
		;;
		
		stat)
		$CPD_SCHED_CONFIG print | awk 'BEGIN{res="OFF"}/Task/{flag=0}/ip_block/{flag=1}/Active: true/{if(flag)res="ON"}END{print "ip_block: Malicious IP blocking mechanism status is "res}'
		;;
	
		*)
		echo "Usage:"
		echo "	$SCRIPT_NAME <option>"
		echo "Option:"
		echo "	on: activate blocking the IP addresses in the feeds"
		echo "	off: stops blocking the IP addresses in the feeds"
		echo "	allow: activate bypass for given IP addresses even if they are on the blocking feeds"
		echo "	delete_bypass:  deactivate bypass list"
		echo "	stat: prints the feature status on this GW"
		echo "	run: run the feature immediately"
	esac
else
echo "This utility is supported on GAIA Security Gateway only"
fi
