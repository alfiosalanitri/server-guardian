# server-guardian
This is a simple bash script that monitor the server high cpu and ram usage and check the systemctl services status.
If the ram or cpu usage is greather then limit or a service is failed, send a message to telegram user

## How to use
- `sudo chown -R root: /path/to/server-guardian`
- `sudo chmod 600 /path/to/server-guardian/.config`
- `sudo chmod 640 /path/to/server-guardian/send-alert.txt`
- `sudo chmod 754 /path/to/server-guardian/guardian.sh`
- `sudo crontab -e`
- `* * * * * cd /path/to/server-guardian/ && ./guardian.sh > /dev/null 2>&1`
