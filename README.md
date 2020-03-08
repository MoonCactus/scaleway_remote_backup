# scaleway_remote_backup.sh

Bash script to trigger remote backups of scaleway server instances

Backups are named like `servername-keyword-index`, where
  * `servername` is the name of your scaleway instance
  * `keyword` is whatever you want (better use alphanumeric)
  * `index` is an automatic number that gets incremented on each new backup

Once done, the script destroys the previous backups _that specifically match the given `keyword`_.

Usage:
  * `--token <SCALEWAY_API_TOKEN>`: your private API key (see User Account / Credentials / API Tokens on Scaleway)
  * `--server <SERVER_NAME>`: either the scaleway identifier or the exact name of the server to backup
  * `--status` dumps server status (JSON structure)
  * `--keyword <KEYWORD>`: (requires --server) a keyword to use within the name of the backup.

Omit
  * `--token` for the script to ask interactively (so your API token does not show up in the process list nor shell history)
  * `--server` to display the list of your servers, by id and name
  * `--keyword` to show the list of your backups for the server

# How to benefit from keywords

You can use different keywords for different time scales, like 'daily' and 'weekly'.

Example: the following cronjob programs one daily backup, and two additional backups named 'weekA' and 'weekB'.
The latter are redone each 14 days, but they are 7 days apart. This way, at all times, you know you will have
a backup that is _at least_ one week old (and at most two week old).

Do not forget to reduce "group" and "other" rights on the cron job (i.e. `chmod go-rwx`),
as it contain your highly powerful API token that makes it possible for anyone to destroy your instances,
or create hundreds of them to send spam in your name. You have been warned ;)

```
PATH=/usr/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin
# m  h     dom     mon dow  command
0    0      *       *   *   /root/scaleway_api_calls.sh '01234567-89ab-cdef-0123-456789abcdef' myserver daily
0    2     0-31/14  *   *   /root/scaleway_api_calls.sh '01234567-89ab-cdef-0123-456789abcdef' myserver weekA
0    2     6-31/14  *   *   /root/scaleway_api_calls.sh '01234567-89ab-cdef-0123-456789abcdef' myserver weekB
```

# Notes
  * snapshots are not completely immediate
  * scaleway "bare metal" servers must be powered off before they can be backuped.
  * the script does not really test the input against weird names or keywords
  * better **understand that api tokens will give full control on your saleway server instances to whoever gets one**

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
