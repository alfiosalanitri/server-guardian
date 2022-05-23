#!/bin/bash
#
# This is a simple bash script that monitor the server high cpu and ram usage and check the systemctl services status.
# If the ram or cpu usage is greather then limit or a service is failed, send a message to telegram user
#
# Require telegram bot and telegram user
#
# written by Alfio Salanitri <www.alfiosalanitri.it> and are licensed under MIT license.

# Config
current_path=$(pwd)
config_file="$current_path/.config"
top_report_file="$current_path/top-report.txt"

alert_filename="send-alert.txt"
alert_file="$current_path/$alert_filename"
send_alert=$(cat $alert_file)
send_alert_every_minutes=$(awk -F'=' '/^send_alert_every_minutes=/ { print $2 }' $config_file)

server_name=$(hostname | sed 's/-//g')
memory_perc_limit=$(awk -F'=' '/^memory_perc_limit=/ { print $2 }' $config_file)
disk_space_perc_limit=$(awk -F'=' '/^disk_space_perc_limit=/ { print $2 }' $config_file)

telegram_bot_token=$(awk -F'=' '/^telegram_bot_token=/ { print $2 }' $config_file)
telegram_user_chat_id=$(awk -F'=' '/^telegram_user_chat_id=/ { print $2 }' $config_file)
telegram_title="Server \\- $server_name:"

# Check required config variables
if [ ! -f $config_file ]; then
  printf "Sorry but the config file is required. \n"
  exit 1
fi
if [ "" == "$send_alert_every_minutes" ]; then
  printf "Sorry but the send_alert_every_minutes variable is required.\n"
  exit 1
fi
if [ "" == "$memory_perc_limit" ]; then
  printf "Sorry but the memory_perc_limit variable is required.\n"
  exit 1
fi
if [ "" == "$telegram_bot_token" ]; then
  printf "Sorry but the telegram_bot_token variable is required.\n"
  exit 1
fi
if [ "" == "$telegram_user_chat_id" ]; then
  printf "Sorry but the telegram_user_chat_id variable_ is required.\n"
  exit 1
fi
# function that send the message to telegram with curl
function send_message() {
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

echo "ok"
exit 0

