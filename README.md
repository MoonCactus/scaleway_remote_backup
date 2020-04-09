# scaleway_remote_backup.sh

Bash script to trigger remote backups of scaleway server instances.

Backups are named like `servername-keyword-index`, where
  * `servername` is the name of your scaleway instance
  * `keyword` is whatever you want (better use alphanumeric)
  * `index` is an automatic number that gets incremented on each new backup

Once done, the script destroys the previous backups _that specifically match the given `keyword`_.

Usage:
  * `--token <API_TOKEN>`: either your private API key, or a file that contains the API key
  * `--zone <AVAILABILITY_ZONE>`: the scaleway datacenter that hosts the server, like "PAR 1" or "fr-par-1" (default), or "AMS1", "nl-ams-3"...
  * `--server <SERVER_NAME>`: either the scaleway identifier or the exact name of the server to backup
  * `--status` dumps server status (JSON structure)
  * `--keyword <KEYWORD>`: (requires --server) a keyword to use within the name of the backup.

The `API_TOKEN` must first be generated via the Scaleway web interface in _User Account / Credentials / API Tokens_

Omit
  * `--token` for the script to ask interactively (so your API token does not show up in the process list nor shell history)
  * `--server` to display the list of your servers, by id and name
  * `--keyword` to show the list of your backups for the server

# How to benefit from keywords

You can use different keywords for different time scales, like 'daily' and 'weekly'.

Example: the following cronjob programs one daily backup, and two additional backups named 'weekA' and 'weekB'.
The latter are redone each 14 days, but they are 7 days apart. This way, at all times, you know you will have
a backup that is _at least_ one week old (and at most two week old).

```
PATH=/usr/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin
# m  h     dom     mon dow  user  command
0    18     *       *   *   root  scaleway_remote_backup.sh --token /etc/scw_api_token --server 'myserver' --keyword 'daily' >>/var/log/scw_backups.log 2>&1
0    2     1-31/14  *   *   root  scaleway_remote_backup.sh --token /etc/scw_api_token --server 'myserver' --keyword 'weekA' >>/var/log/scw_backups.log 2>&1
0    2     7-31/14  *   *   root  scaleway_remote_backup.sh --token /etc/scw_api_token --server 'myserver' --keyword 'weekB' >>/var/log/scw_backups.log 2>&1
```

Simpler even, you can also program a 7-day rolling backup by using the day of week as the token:
```
0    0      *       *   *   root  scaleway_remote_backup.sh --token /etc/scw_api_token --server 'myserver' --keyword "$(date +%a|cut -c1-3)" >>/var/log/scw_backups.log 2>&1
```

Never forget to hide your API token from groups and others (i.e. `chmod go-rwx /etc/scw_api_token` above).
It contains what is needed to destroy your instances and create hundreds of them to send spam in your name!

# Notes & disclaimer
  * this scripts uses `jq`, a nice tool to parse JSON
  * snapshots are not completely immediate
  * scaleway "bare metal" servers must be powered off before they can be backuped.
  * the script does not really test the input against weird names or keywords
  * once again **anyone who knows your api token will have full control on your scaleway instances**

# Exit states

| Errno | Meaning           |
|-------|-------------------|
|   0   | success           |
|   1   | usage             |
|   2   | missing jq tool   |
|   3   | invalid API token |
|   4   | server not found  |
|   5   | unstable server   |
|   6   | backup failed     |
