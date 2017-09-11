#!/bin/bash
# Just a simple cleanup script so we don't leave
# a bunch of history behind at build-time
# THIS IS NOT AN END-USER SCRIPT
# Running this will DESTROY all your NEMS configuration and reset to factory defaults

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 2>&1
  exit 1
else
  
  if [[ $1 != "halt" ]]; then echo "Pass the halt option to halt after execution or the reboot option to reboot."; echo ""; fi;
  
  sync
  
  echo "Did you cp the database? This script will restore from Migrator. CTRL-C to abort."
  sleep 5
  
  # Stop services which may be using these files
  systemctl stop webmin
  systemctl stop rpimonitor
  systemctl stop monitorix
  systemctl stop apache2
  systemctl stop nagios3
  
  touch /tmp/nems.freeze

  sudo apt-get clean
  sudo apt-get autoclean
  apt-get autoremove

  echo "Don't forget to remove the old kernels:"
  dpkg --get-selections | grep linux-image

  # Empty old logs
  find /var/log/ -type f -exec cp /dev/null {} \;
  find /var/log/ -iname "*.gz" -type f -delete
  find /var/log/ -iname "*.log.*" -type f -delete
  rm /var/log/nagios3/archives/*.log

  # Clear system mail
  find /var/mail/ -type f -exec cp /dev/null {} \;

  # Remove Webmin logs and sessions
  rm /var/webmin/webmin.log
  rm /var/webmin/miniserv.log
  rm /var/webmin/miniserv.error
  rm /var/webmin/sessiondb.pag
  
  # Clear RPi-Monitor history and stats
  rm /usr/share/rpimonitor/web/stat/*.rrd
  
  # Clear Monitorix history, stats and config
  echo "" > /etc/monitorix/conf.d/nems.conf
  rm /var/lib/monitorix/*.rrd
  rm /var/log/monitorix*
  rm /var/lib/monitorix/www/imgs/*.png
  rm /var/lib/monitorix/usage/*
  
  cd /root
  rm .nano_history
  rm .bash_history

  cd /home/pi
  rm .nano_history
  rm .bash_history

  rm /var/log/lastlog
  touch /var/log/lastlog

  # remove config backup from NEMS-Migrator
  rm /var/www/html/backup/backup.nems

  # Remove DNS Resolver config (will be auto-generated on first boot)
  rm  /etc/resolv.conf

  # remove output from nconf
  rm /var/www/nconf/output/*

  # Remove NEMS init password file
  rm /var/www/htpasswd

  # Remove benchmark file
  rm /var/log/nems-benchmark.log

  # Reset pi Linux User password to "raspberry"
  pipassword="raspberry"
  echo -e "$pipassword\n$pipassword" | passwd pi >/tmp/init 2>&1
  
  # Reset Nagios Core User
  cp -f /root/nems/nems-migrator/data/nagios/cgi.cfg /etc/nagios3/
  
  # Reset Check_MK User
  cp -f /root/nems/nems-migrator/data/check_mk/users.mk /etc/check_mk/multisite.d/wato/users.mk

  # Reininitialize Nagios3 user account
  echo "define contactgroup {
                  contactgroup_name                     admins
                  alias                                 Nagios Administrators
                  members                               nagiosadmin
  }
  " > /etc/nagios3/global/contactgroups.cfg
  echo "define contact {
                  contact_name                          nagiosadmin
                  alias                                 Nagios Admin
                  host_notification_options             d,u,r,f,s
                  service_notification_options          w,u,c,r,f,s
                  email                                 nagios@localhost
                  host_notification_period              24x7
                  service_notification_period           24x7
                  host_notification_commands            notify-host-by-email
                  service_notification_commands         notify-service-by-email
  }
  " > /etc/nagios3/global/contacts.cfg
  
  # Replace the database with Sample database
  systemctl stop mysql
  rm -rf /var/lib/mysql/
  cp -R /root/nems/nems-migrator/data/mysql/NEMS-Sample /var/lib
  chown -R mysql:mysql /var/lib/NEMS-Sample
  mv /var/lib/NEMS-Sample /var/lib/mysql
  systemctl start mysql
  
  # Remove nconf history, should it exist
  mysql -u nconf -pnagiosadmin nconf -e "TRUNCATE History"

  # Sync the current running version as the current available version
  # Will be overwritten on first boot
  cp /root/nems/ver.txt /var/www/html/inc/ver-available.txt
  
  # Replace installed certs with defaults
  rm -rf /var/www/certs/
  cp -R /root/nems/nems-migrator/data/certs /var/www
  chown -R root:root /var/www/certs

  sync
  
  if [[ $1 == "halt" ]]; then echo "Halting..."; halt; exit; fi;

  if [[ $1 == "reboot" ]]; then echo "Rebooting..."; reboot; exit; fi;

  # System still running: Restart services
  service networking restart
  systemctl start webmin
  systemctl start rpimonitor
  systemctl start monitorix
  systemctl start apache2
  systemctl start nagios3
  rm /tmp/nems.freeze
  
fi
