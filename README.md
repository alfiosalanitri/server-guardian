# server-guardian
A simple bash script to monitor the server high cpu, ram usage and systemctl services status that send an alert to telegram bot.

## How to use
- `sudo chown -R root: /path/to/server-guardian`
- `sudo chmod 600 /path/to/server-guardian/.config`
- `sudo chmod 640 /path/to/server-guardian/send-alert.txt`
- `sudo chmod 754 /path/to/server-guardian/guardian.sh`
- `sudo crontab -e`
- `* * * * * cd /path/to/server-guardian/ && ./guardian.sh > /dev/null 2>&1`
