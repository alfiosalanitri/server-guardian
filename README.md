# server-guardian
This is a simple bash script that monitor the server high cpu and ram usage, check the systemctl services status and the hard disk free space.
If the ram or cpu usage is greather then limit or a service is failed or the disk usage is greather then limit, send a message to telegram user

## How to use
- `sudo chown -R root:root /path/to/server-guardian`
- `sudo cp /path/to/server-guardian/.config.demo /path/to/server-guardian/.config` 
- edit .config file and type your telegram bot key and chat or adjust the options
- `sudo chmod 600 /path/to/server-guardian/.config`
- `sudo chmod 640 /path/to/server-guardian/send-alert.txt`
- `sudo chmod 754 /path/to/server-guardian/guardian`
- `sudo crontab -e`
- `* * * * * cd /path/to/server-guardian/ && ./guardian > /dev/null 2>&1`

## Advanced Use
- `* * * * * cd /path/to/server-guardian/ && ./guardian --warn-every 30 --watch-services 0 --watch-cpu 1 --watch-ram 1 --watch-hard-disk 0 --cpu-warning-level high --memory-limit 60 --disk-space-limit 80 --config /home/my-custom/.config --config-telegram-variable-token TELEGRAM_TOKEN_CUSTOM_NAME --config-telegram-variable-chatid TELEGRAM_CHAT_ID_CUSTOM_NAME > /dev/null 2>&1`

**Note**: when you pass an option, this will overrides the default value stored into config file.

### Options
`--warn-every` Minutes number between each alert
    
`--watch-cpu` 1 to enable or 0 to disable the high cpu usage
    
`--watch-ram` 1 to enable or 0 to disable the high ram usage
    
`--watch-services` 1 to enable or 0 to disable the services failed alert
    
`--watch-hard-disk` 1 to enable or 0 to disable the hard disk free space alert
    
`--cpu-warning-level` 
- **high**: to receive an alert if the load average of last minute is greater than cpu core number. 
- **medium**: watch the value of the latest 5 minutes. (default)
- **low**: watch the value of the latest 15 minuts.
    
`--memory-limit` Memory percentage limit
    
`--disk-space-limit` disk space percentage limit
    
`--config` path to custom config file with telegram bot key and telegram chat id options
    
`--config-telegram-variable-token` the token variable name (not the token key) stored in custom config file (ex: TELEGRAM_TOKEN_CUSTOM_NAME)
    
`--config-telegram-variable-chatid` the chat id variable name (not the id) stored in custom config file (ex: TELEGRAM_CHAT_ID_CUSTOM_NAME)
    
`-h, --help` show this help
