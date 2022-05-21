# server-guardian
This is a simple bash script that monitor the server high cpu and ram usage, check the systemctl services status and the hard disk free space.
If the ram or cpu usage is greather then limit or a service is failed or the disk usage is greather then limit, send a message to telegram user

## How to use
- `sudo chown -R root:root /path/to/server-guardian`
- `sudo cp /path/to/server-guardian/.config.demo /path/to/server-guardian/.config` 
- edit .config file and type your telegram bot key and chat or adjust the options
- `sudo chmod 600 /path/to/server-guardian/.config`
- `sudo chmod 640 /path/to/server-guardian/send-alert.txt`
- `sudo chmod 754 /path/to/server-guardian/guardian.sh`
- `sudo crontab -e`
- `* * * * * cd /path/to/server-guardian/ && ./guardian.sh > /dev/null 2>&1`
