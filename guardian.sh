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

Usage: $(basename $0) --warn-every 60 --watch-services 1 --watch-cpu 1 --watch-ram 1 --watch-hard-disk 1 --watch-supervisor 1 --cpu-warning-level low --memory-limit 70 --disk-space-limit 80 --config /path/to/.custom-config --config-telegram-variable-token TELEGRAM_TOKEN --config-telegram-variable-chatid CHAT_ID

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

--watch-supervisor
    1 to enable or 0 to disable the supervisor failed processes alert

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
    
--test
    test if the bot is working

-h, --help
    show this help
-------------
EOF
exit 0
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
      echo "Ready for send an alert."
      exit 0
    fi
    minutes_to_next_alert=$(($send_alert_every_minutes - $minutes_elapsed))
    echo "The sessage has been sent $minutes_elapsed minutes ago. The next one will be sent in $minutes_to_next_alert minutes." 
    exit 0
  fi
  # send the message and store the word no to txt file
  echo "no" > $alert_file
  echo "Ok the message has been sent. The next one will be sent in $send_alert_every_minutes minutes." 
  
  telegram_message="\`$(echo "$1" | sed "s/\./-/g")\`"
  
  # store top results to file
  if [ "yes" == $2 ]; then
    top -n1 -b > $top_report_file
  fi
  
  curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -F chat_id=$telegram_user_chat_id -F text="$telegram_title $telegram_message" -F parse_mode="MarkdownV2"

  exit 0
}

# test if telegram api works
send_test_message() {
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -F chat_id=$telegram_user_chat_id -F text="$telegram_title Ok the server guardian is working" -F parse_mode="MarkdownV2")
  if [ "$response" != "200" ]; then
    printf "Error: Telegram API returned HTTP $response. Check your bot token and chat ID.\n"
    exit 1
  fi
  echo "Test message sent successfully."
  exit 0
}

##########################
# Default options
##########################
server_name=$(hostname)
current_path=$(pwd)
top_report_file="$current_path/top-report.txt"
alert_filename="send-alert.txt"
alert_file="$current_path/$alert_filename"
#create the alert and top report file only the first time
if [ ! -f $alert_file ]; then
  echo "yes" > $alert_file
fi
if [ ! -f $top_report_file ]; then
  echo "" > $top_report_file
fi
send_alert=$(cat $alert_file)
config_file=""
send_alert_every_minutes=""
watch_cpu=""
cpu_warning_level=""
watch_ram=""
memory_perc_limit=""
watch_services=""
watch_hard_disk=""
disk_space_perc_limit=""
watch_supervisor=""
telegram_title="\[ Server \`$server_name\` \] \\-\\-"
telegram_variable_token="telegram_bot_token"
telegram_variable_chatid="telegram_user_chat_id"
send_test="no"

##########################
# Get options from cli
##########################
while [ $# -gt 0 ] ; do
  case $1 in
    -h | --help) 
      display_help 
      ;;
    --test) 
      send_test="yes"
      ;;
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
    --watch-supervisor)
      watch_supervisor=$2
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
# Check options and config
##########################
if [ "" == "$config_file" ]; then
  # .env is the current default; fall back to the legacy .config name
  # for installs that predate the .env rename.
  if [ -f "$current_path/.env" ]; then
    config_file="$current_path/.env"
  elif [ -f "$current_path/.config" ]; then
    config_file="$current_path/.config"
  else
    config_file="$current_path/.env"
  fi
fi
if [ ! -f $config_file ]; then
  printf "Sorry but the config file is required. \n"
  exit 1
fi

# When only testing the bot, supply defaults so monitoring validation is skipped
if [ "yes" == "$send_test" ]; then
  send_alert_every_minutes="${send_alert_every_minutes:-60}"
  watch_cpu="${watch_cpu:-0}"
  cpu_warning_level="${cpu_warning_level:-medium}"
  watch_ram="${watch_ram:-0}"
  memory_perc_limit="${memory_perc_limit:-80}"
  watch_services="${watch_services:-0}"
  watch_hard_disk="${watch_hard_disk:-0}"
  disk_space_perc_limit="${disk_space_perc_limit:-80}"
  watch_supervisor="${watch_supervisor:-0}"
fi

if [ "" == "$send_alert_every_minutes" ]; then
  send_alert_every_minutes=$(awk -F'=' '/^send_alert_every_minutes=/ { print $2 }' $config_file)
fi
if [ "" == "$send_alert_every_minutes" ]; then
  printf "Pass the --warn-every variable from cli or add send_alert_every_minutes variable to config file.\n"
  exit 1
fi

if [ "" == "$watch_cpu" ]; then
  watch_cpu=$(awk -F'=' '/^watch_cpu=/ { print $2 }' $config_file)
fi
if [ "" == "$watch_cpu" ]; then
  printf "Pass the --watch-cpu variable from cli or add watch_cpu variable to config file.\n"
  exit 1
fi
if [ "" == "$cpu_warning_level" ]; then
  cpu_warning_level=$(awk -F'=' '/^cpu_warning_level=/ { print $2 }' $config_file)
fi
if [ "" == "$cpu_warning_level" ] && [ "1" == "$watch_cpu" ]; then
  printf "Pass the --cpu-warning-level variable from cli or add cpu_warning_level variable to config file.\n"
  exit 1
fi

if [ "" == "$watch_ram" ]; then
  watch_ram=$(awk -F'=' '/^watch_ram=/ { print $2 }' $config_file)
fi
if [ "" == "$watch_ram" ]; then
  printf "Pass the --watch-ram variable from cli or add watch_ram variable to config file.\n"
  exit 1
fi
if [ "" == "$memory_perc_limit" ]; then
  memory_perc_limit=$(awk -F'=' '/^memory_perc_limit=/ { print $2 }' $config_file)
fi
if [ "" == "$memory_perc_limit" ] && [ "1" == "$watch_ram" ]; then
  printf "Pass the --memory-limit variable from cli or add memory_perc_limit variable to config file.\n"
  exit 1
fi

if [ "" == "$watch_services" ]; then
  watch_services=$(awk -F'=' '/^watch_services=/ { print $2 }' $config_file)
fi
if [ "" == "$watch_services" ]; then
  printf "Pass the --watch-services variable from cli or add watch_services variable to config file.\n"
  exit 1
fi

if [ "" == "$watch_hard_disk" ]; then
  watch_hard_disk=$(awk -F'=' '/^watch_hard_disk=/ { print $2 }' $config_file)
fi
if [ "" == "$watch_hard_disk" ]; then
  printf "Pass the --watch-hard-disk variable from cli or add watch_hard_disk variable to config file.\n"
  exit 1
fi
if [ "" == "$disk_space_perc_limit" ]; then
  disk_space_perc_limit=$(awk -F'=' '/^disk_space_perc_limit=/ { print $2 }' $config_file)
fi
if [ "" == "$disk_space_perc_limit" ] && [ "1" == "$watch_hard_disk" ]; then
  printf "Pass the --disk-space-limit variable from cli or add disk_space_perc_limit variable to config file.\n"
  exit 1
fi

# watch_supervisor is optional: default to disabled so configs and installs
# that predate this feature keep working without changes.
if [ "" == "$watch_supervisor" ]; then
  watch_supervisor=$(awk -F'=' '/^watch_supervisor=/ { print $2 }' $config_file)
fi
watch_supervisor="${watch_supervisor:-0}"

# Check telegram bot key and chat id
telegram_bot_token=$(awk -F'=' -v k="$telegram_variable_token" '$1 == k { print $2 }' "$config_file")
if [ "" == "$telegram_bot_token" ]; then
  printf "The variable $telegram_variable_token not exists into config file or is empty.\n"
  exit 1
fi
telegram_user_chat_id=$(awk -F'=' -v k="$telegram_variable_chatid" '$1 == k { print $2 }' "$config_file")
if [ "" == "$telegram_user_chat_id" ]; then
  printf "The variable $telegram_variable_chatid not exists into config file or is empty.\n"
  exit 1
fi

if [ "yes" == "$send_test" ]; then
  send_test_message
fi


##########################
# Start monitor
##########################
# Get the load average value and if is greather than 100% send an alert and exit
if [ "1" == "$watch_cpu" ]; then
  server_core=$(lscpu | grep '^CPU(s)' | awk '{print int($2)}')
  load_avg=$(uptime | grep -ohe 'load average[s:][: ].*')
  avg_position='$4' #avg 5min
  case $cpu_warning_level in 
    low)
      avg_position='$5' #avg 15min
      ;;
    high)
      avg_position='$3' #avg 1min
      ;;
  esac
  load_avg_for_minutes=$(uptime | grep -ohe 'load average[s:][: ].*' | awk '{ print '$avg_position'}' | sed -e 's/,/./' | sed -e 's/,//' | awk '{print int($1)}')
  if [ -n "$server_core" ] && [ "$server_core" -gt 0 ]; then
    load_avg_percentage=$(($load_avg_for_minutes * 100 / $server_core))
    if [ $load_avg_percentage -ge 100 ]; then
      message="High CPU usage: $load_avg_percentage% - $load_avg (1min, 5min, 15min)"
      send_message "$message" "yes"
    fi
  fi
fi

# Get the ram usage value and if is greather then limit, send the message and exit
if [ "1" == "$watch_ram" ]; then
  ram_usage=$(free | awk '/Mem/{printf("RAM Usage: %.0f\n"), $3/$2*100}'| awk '{print $3}')
  if [ "$ram_usage" -gt $memory_perc_limit ]; then
    message="High RAM usage: $ram_usage%"
    send_message "$message" "yes"
  fi
fi


# Check the systemctl services and if one or more are failed, send an alert and exit
if [ "1" == "$watch_services" ]; then
  services=$(sudo systemctl --failed | awk '{if (NR!=1) {print}}' | head -2)
  if [[ $services != *"0 loaded"* ]]; then
    message="Systemctl failed services: $services"
    send_message "$message" "no"
  fi
fi

# Check the supervisor processes and if one or more are FATAL/BACKOFF, send an alert and exit
if [ "1" == "$watch_supervisor" ]; then
  if command -v supervisorctl >/dev/null 2>&1; then
    supervisor_failed=$(sudo supervisorctl status 2>/dev/null | grep -Ei "FATAL|BACKOFF")
    if [ -n "$supervisor_failed" ]; then
      message="Supervisor failed processes: $supervisor_failed"
      send_message "$message" "no"
    fi
  fi
fi

# Check the free disk space
if [ "1" == "$watch_hard_disk" ]; then
  disk_perc_used=$(df / --output=pcent | tr -cd 0-9)
  if [ "$disk_perc_used" -gt $disk_space_perc_limit ]; then
    message="Hard disk full (space used $disk_perc_used%)"
    send_message "$message" "no"
  fi
fi

echo "it's all right."
exit 0
