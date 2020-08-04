#!/bin/bash

SCRIPT_NAME=$0
LOCAL_TMP_LOG_FILE="$FWDIR/tmp/block_ip.tmp"
LOG_FILE="$FWDIR/log/ip_block_activate.log"


action=""

function log_line {
	# add timestamp to all log lines
	message=$1
	local_log_file=$2
	echo "$(date) $message" >> $local_log_file
}

#for each gw do
function run_gw_list {
     while read gw_ip; do
        if [ ! -z "$gw_ip" ] && [ ${gw_ip:0:1} != "#" ]
        then
        	log_line "gw_ip: $gw_ip" $LOG_FILE
			
			#get FWDIR from gw
			remote_fwdir=$(cprid_util -server $gw_ip getenv -attr "FWDIR")
			if  [ -z "$remote_fwdir" ]
			then
				echo "Error: could not retrieve FWDIR from $gw_ip" 1>&2; 
				log_line "Error: could not retrieve FWDIR from $gw_ip" $LOG_FILE
				exit 1
			fi

			remote_feed_file="$remote_fwdir/database/block_ip_feeds_gw.txt"
			remote_bypass_file="$remote_fwdir/database/block_ip_bypass_feed_gw.txt"
			REMOTE_TMP_LOG_FILE="$remote_fwdir/tmp/block_ip.tmp"
			
			remote_fwdir=$(cprid_util -server $gw_ip -stdout $REMOTE_TMP_LOG_FILE getenv -attr "FWDIR")

			if  [ -z "$remote_fwdir" ]
			then
				echo "Error: could not retrieve FWDIR from $gw_ip" 1>&2; 
				log_line "Error: could not retrieve FWDIR from $gw_ip" $LOG_FILE
				exit 1
			fi

			remote_script_file="$remote_fwdir/bin/ip_block.sh"
			
			log_line "verify $remote_script_file exists on $gw_ip" $LOG_FILE
			runme=$(cprid_util -server $gw_ip -stdout $REMOTE_TMP_LOG_FILE rexec -rcmd ls $remote_script_file)
			result=$(cprid_util -server $gw_ip getfile -local_file $LOCAL_TMP_LOG_FILE -remote_file $REMOTE_TMP_LOG_FILE)
			does_file_exist=$(cat $LOCAL_TMP_LOG_FILE)
			log_line "done" $LOG_FILE
			#if the file script does not exist on the server
			if [ -z $does_file_exist ]
			then
				echo "Error: $remote_script_file does not exist on $gw_ip"
				return
			fi
			
			

			if [ "$action" = "on" ]
			then
				log_line "Moving $remote_feed_file to $gw_ip" $LOG_FILE
				move_feed=$(cprid_util -server $gw_ip putfile -local_file $local_feed_file -remote_file $remote_feed_file)
				log_line "done" $LOG_FILE
			fi

			if [ "$action" = "allow" ]
			then
				log_line "moving $remote_bypass_file to $gw_ip" $LOG_FILE
				move_feed=$(cprid_util -server $gw_ip putfile -local_file $local_bypass_file -remote_file $remote_bypass_file)
				log_line "done" $LOG_FILE
			fi
			
			log_line "Running $remote_script_file $action on $gw_ip" $LOG_FILE
			runme=$(cprid_util -server $gw_ip -stdout $REMOTE_TMP_LOG_FILE rexec -rcmd $remote_script_file $action)
			log_line "done" $LOG_FILE
			
			result=$(cprid_util -server $gw_ip getfile -local_file $LOCAL_TMP_LOG_FILE -remote_file $REMOTE_TMP_LOG_FILE)
			echo "$gw_ip response:"
			cat $LOCAL_TMP_LOG_FILE
			cat $LOCAL_TMP_LOG_FILE >> $LOG_FILE
        fi
     done 
}

function copy_script_to_gw {
	 #for each gw do
     while read gw_ip; do
        if [ ! -z "$gw_ip" ] && [ ${gw_ip:0:1} != "#" ]
        then
			remote_fwdir=$(cprid_util -server $gw_ip getenv -attr "FWDIR")
			if  [ -z "$remote_fwdir" ]
			then
				echo "Error: could not retrieve FWDIR from $gw_ip" 1>&2; 
				log_line "Error: could not retrieve FWDIR from $gw_ip" $LOG_FILE
				exit 1
			fi
			remote_script_file="$remote_fwdir/bin/ip_block.sh"
			
			copy_script=$(cprid_util -server $gw_ip putfile -local_file $script_file -remote_file $remote_script_file)
			#give +x permissions
			runme=$(cprid_util -server $gw_ip rexec -rcmd chmod +x $remote_script_file)
		fi
	done
}

#help info
usage() { 
	echo "Usage: $0 -a <on|off|stat|allow> [-g <gw_list_file>] [-b <bypass_file>] [-f <feed_file>] [-s <script_file>]" 1>&2; 
	echo "Option:" 1>&2; 
	echo "	-a on: activate blocking the IP addresses in the feeds" 1>&2; 
	echo "	-a off: stops blocking the IP addresses in the feeds" 1>&2; 
	echo "	-a stat: prints the feature status of each GW" 1>&2; 
	echo "	-a allow: activate bypass for given IP addresses even if they are on the blocking feeds" 1>&2; 
	echo "	-a delete_bypass: deactivate bypass list" 1>&2; 
	echo "	-g gw_list_file: a list of GW IPs" 1>&2; 
	echo "	-b bypass_file: a list of IPs to bypass" 1>&2; 
	echo "	-f feed_file: a list of feeds URLs with IPs to block" 1>&2; 
	echo "	-s script_file: full path to ip_block.sh to copy to the GWs" 1>&2; 
	echo "Example:" 1>&2; 
	echo "	$0 -a on -g local_gw_file -f local_feed_list"
	exit 1; 
}


while getopts ":a:g:b:f:s:" o; do
	case "${o}" in
        a)
			op=${OPTARG}
            ((op == "on" || op == "off" || op == "stat" || op == "allow" || op == "delete_bypass")) || usage
            ;;
        g)
            gw_list_file=${OPTARG}
            ;;
		b)
            local_bypass_file=${OPTARG}
            ;;
		f)
            local_feed_file=${OPTARG}
            ;;
		s)
			script_file=${OPTARG}
			;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


if  [ -z "$op" ] 
then
	usage
fi

if  [ -z "$gw_list_file" ]
then
	echo "Error: missing gw list file" 1>&2;
	usage
fi

#copy the script to the GWs if we have a script file
if  [ -n "$script_file" ]
then
	cat $gw_list_file | grep -vE '^$'| copy_script_to_gw
fi

case "$op" in
	on)
	if  [ -z "$local_feed_file" ]
	then
		echo "Error: missing feed file" 1>&2;
		usage
	fi
	action=on
	cat $gw_list_file | grep -vE '^$'| run_gw_list
	;;

	off)
	action=off
	cat $gw_list_file | grep -vE '^$'| run_gw_list
	;;

	stat)
	action=stat
	cat $gw_list_file | grep -vE '^$'| run_gw_list
	;;
	
	delete_bypass)
	action=delete_bypass
	cat $gw_list_file | grep -vE '^$'| run_gw_list
	;;
	
	allow)
	if  [ -z "$local_bypass_file" ]
	then
		echo "Error: missing bypass file" 1>&2;
		usage
	fi
	action=allow
	
	cat $gw_list_file | grep -vE '^$'| run_gw_list
	;;

	*)
	
	usage
esac
