#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 2>&1
  exit 1
else
  # Ping Google to see if Internet is up. Don't begin until we have Internet.
  while ! ping -c 1 -W 1 google.com; do
    sleep 1
  done

  # Tell the web cache to serve up the file from midnight
  timestamp=$( /bin/date --date="today 00:00:01 UTC -5 hours" +%s )
  /usr/bin/wget -q -O /var/www/html/inc/ver-available.txt http://cdn.zecheriah.com/baldnerd/nems/ver-current.txt#$timestamp
  
  # Update nems-migrator
  cd /root/nems/nems-migrator && git pull

  # Update self
  cd /home/pi/nems-scripts && git pull

  # Copy the version data to the public inc folder (in case it accidentally gets deleted)
  test -d "/var/www/html/inc" || mkdir -p "/var/www/html/inc" && cp /root/nems/ver.txt "/var/www/html/inc"
fi
