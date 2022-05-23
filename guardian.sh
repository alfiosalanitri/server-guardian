#!/bin/bash
#
# This is a simple bash script that monitor the server high cpu and ram usage and check the systemctl services status.
# If the ram or cpu usage is greather then limit or a service is failed, send a message to telegram user
#
# Require telegram bot and telegram user
#
# written by Alfio Salanitri <www.alfiosalanitri.it> and are licensed under MIT license.

##########################
# Functions
##########################
display_help() {
cat << EOF
Copyright (C) 2022 by Alfio Salanitri
Website: https://github.com/alfiosalanitri/server-guardian

Usage: $(basename $0) --warn-every 60 --watch-services 1 --watch-cpu 1 --watch-ram 1 --watch-hard-disk 1 --cpu-warning-level low --memory-limit 70 --disk-space-limit 80 --config /path/to/.custom-config --config-telegram-variable-token TELEGRAM_TOKEN --config-telegram-variable-chatid CHAT_ID

Options
--warn-every
    Minutes number between each alert
    
--watch-cpu
    1 to enable or 0 to disable the high cpu usage
    
--watch-ram
    1 to enable or 0 to disable the high ram usage
    
--watch-services
    1 to enable or 0 to disable the services failed alert
    
--watch-hard-disk
    1 to enable or 0 to disable the hard disk free space alert
    
--cpu-warning-level
    high: to receive an alert if the load average of last minute is greater than cpu core number. 
    medium: watch the value of the latest 5 minutes. (default)
    low: watch the value of the latest 15 minuts.
    
--memory-limit
    Memory percentage limit
    
--disk-space-limit
    disk space percentage limit
    
--config
    path to custom config file with telegram bot key and telegram chat id options
    
--config-telegram-variable-token
    the token variable name (not the token key) stored in custom config file (ex: TELEGRAM_TOKEN)
    
--config-telegram-variable-chatid
    the chat id variable name (not the id) stored in custom config file (ex: TELEGRAM_CHAT_ID)
    
-h, --help
    show this help
-------------
EOF
}
# send the message to telegram with curl
send_message() {
  # Check the send-alert.txt content, it prevents the message from being sent every minute 
  if [ "no" == "$send_alert" ]; then
    # Get the file edit time and current time, if elapsed minutes is greater than config variable, save the word yes to file to send another message on next cron check.
    current_time=$(date +%s)
    edit_filetime=$(stat -c %Y $alert_file | sed "s/$alert_filename//")
    minutes_elapsed=$((10#$(($current_time - $edit_filetime)) / 60))
    if [ $minutes_elapsed -gt $send_alert_every_minutes ]; then
      echo "yes" > $alert_file
    fi
    exit 1
  fi
  # send the message and store the word no to txt file
  echo "no" > $alert_file
  
  telegram_message="\`$1\`"
  
  # store top results to file
  if [ "yes" == $2 ]; then
    top -n1 -b > $top_report_file
    telegram_message="${telegram_message}. See top results here: $top_report_file"
  fi
  
  curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -F chat_id=$telegram_user_chat_id -F text="$telegram_title $telegram_message" -F parse_mode="MarkdownV2"

  exit 1
}

##########################
# Default options
##########################
server_name=$(hostname | sed 's/-//g')
current_path=$(pwd)
top_report_file="$current_path/top-report.txt"
alert_filename="send-alert.txt"
alert_file="$current_path/$alert_filename"
send_alert=$(cat $alert_file)
config_file=""
send_alert_every_minutes=""
watch_cpu=""
watch_ram=""
watch_services=""
watch_hard_disk=""
cpu_warning_level=""
memory_perc_limit=""
disk_space_perc_limit=""
telegram_title="Server \\- $server_name:"
telegram_variable_token="telegram_bot_token"
telegram_variable_chatid="telegram_user_chat_id"

##########################
# Get options from cli
##########################
while [ $# -gt 0 ] ; do
  case $1 in
    -h | --help) display_help ;;
    --warn-every)
      send_alert_every_minutes=$2 
      ;;
    --watch-cpu)
      watch_cpu=$2 
      ;;
    --watch-ram)
      watch_ram=$2 
      ;;
    --watch-services)
      watch_services=$2 
      ;;
    --watch-hard-disk)
      watch_hard_disk=$2 
      ;;
    --cpu-warning-level)
      cpu_warning_level=$2 
      ;;
    --memory-limit)
      memory_perc_limit=$2
      ;;
    --disk-space-limit)
      disk_space_perc_limit=$2
      ;;
    --config)
      if [ ! -f $2 ]; then
        printf "Sorry but this config file not exists.\n"
        exit 1
      fi
      config_file=$2
      ;;
    --config-telegram-variable-token)
      telegram_variable_token=$2
      ;;
    --config-telegram-variable-chatid)
      telegram_variable_chatid=$2
      ;;
  esac
  shift
done

##########################
# Check options
##########################
if [ "" == "$config_file" ]; then
  config_file="$current_path/.config"
fi
if [ ! -f $config_file ]; then
  printf "Sorry but the config file is required. \n"
  exit 1
fi

if [ "" == "$send_alert_every_minutes" ]; then
  send_alert_every_minutes=$(awk -F'=' '/^send_alert_every_minutes=/ { print $2 }' $config_file)
fi
if [ "" == "$send_alert_every_minutes" ]; then
  printf "Pass the --warn-every variable from cli or add send_alert_every_minutes variable to config file.\n"
  exit 1
fi

# check memory percentage limit value if watch_ram is enabled
if [ "" == "$memory_perc_limit" ]; then
  memory_perc_limit=$(awk -F'=' '/^memory_perc_limit=/ { print $2 }' $config_file)
fi
if [ "" == "$memory_perc_limit" ] && [ "1" == "$watch_ram" ]; then
  printf "Pass the --memory-limit variable from cli or add memory_perc_limit variable to config file.\n"
  exit 1
fi

# check disk space percentage limit value if watch_ram is enabled
if [ "" == "$disk_space_perc_limit" ]; then
  disk_space_perc_limit=$(awk -F'=' '/^disk_space_perc_limit=/ { print $2 }' $config_file)
fi
if [ "" == "$disk_space_perc_limit" ] && [ "1" == "$watch_hard_disk" ]; then
  printf "Pass the --disk-space-limit variable from cli or add disk_space_perc_limit variable to config file.\n"
  exit 1
fi

# Check telegram bot key and chat id
telegram_bot_token=$(awk '/^token=/ { print $2 }' $config_file)
telegram_user_chat_id=$(awk -F'=' '/^chat=/ { print $2 }' $config_file)

echo $telegram_bot_token
echo $telegram_user_chat_id
exit 1
if [ "" == "$telegram_bot_token" ]; then
  printf "Sorry but the $telegram_variable_token variable is required.\n"
  exit 1
fi
if [ "" == "$telegram_user_chat_id" ]; then
  printf "Sorry but the $telegram_user_chat_id variable is required.\n"
  exit 1
fi



# Get the ram usage value and if is greather then limit, send the message and exit
ram_usage=$(free | awk '/Mem/{printf("RAM Usage: %.0f\n"), $3/$2*100}'| awk '{print $3}')
if [ "$ram_usage" -gt $memory_perc_limit ]; then
  message="High RAM usage: $ram_usage%"
  send_message "$message" "yes"
fi

# Get the load average value and if is greather than 100% send an alert and exit
server_core=$(lscpu | grep '^CPU(s)' | awk '{print int($2)}')
load_avg=$(uptime | grep -ohe 'load average[s:][: ].*')
load_avg_last_minute=$(uptime | grep -ohe 'load average[s:][: ].*' | awk '{ print $3 }' | sed -e 's/,/./' | sed -e 's/,//' | awk '{print int($1)}')
load_avg_percentage=$(($load_avg_last_minute * 100 / $server_core))
if [ $load_avg_percentage -gt 100 ]; then
  message="High CPU usage: $load_avg_percentage% - $load_avg (1min, 5min, 15min)"
  echo $message
fi

# Check the systemctl services and if one or more are failed, send an alert and exit
services=$(sudo systemctl --failed | awk '{if (NR!=1) {print}}' | head -2)
if [[ $services != *"0 loaded"* ]]; then
  message="Systemctl failed services: $services"
  send_message "$message" "no"
fi

# Check the free disk space
disk_perc_used=$(df / --output=pcent | tr -cd 0-9)
if [ "$disk_perc_used" -gt $disk_space_perc_limit ]; then
  message="Hard disk full (space used $disk_perc_used%)"
  send_message "$message" "no"
fi

echo "it's all right."
exit 0