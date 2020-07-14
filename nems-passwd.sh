#!/bin/bash
ver=$(/usr/local/share/nems/nems-scripts/info.sh nemsver)
platform=$(/usr/local/share/nems/nems-scripts/info.sh platform)
init=$(/usr/local/share/nems/nems-scripts/info.sh init)
tmpdir=`mktemp -d -p /usr/local/share/`
username=$(/usr/local/share/nems/nems-scripts/info.sh username)

echo ""
echo -e "\e[1mNEMS Linux Change Password\e[0m"
echo ""
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 2>&1
  exit 1
else

  if [[ $init = 1 ]]; then
    echo -e "Changing password for user: \e[1m$username\e[0m (CTRL-C to abort)"
    read -r -p "Continue? [y/N] " beta
    echo ""
    if [[ $beta =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo "Proceeding..."
    else
      echo "Aborted."
      exit 1
    fi
  else
    echo
    echo "Your NEMS Server is not yet initialized, so password cannot be changed."
    echo
    exit 1
  fi

  echo -e "\e[0m"

  while true; do
    read -s -p "New Password: " password
    echo
    read -s -p "New Password (again): " password2
    echo
    [ "$password" = "nemsadmin" ] && password="-" && echo "You are not allowed to use that password."
    [ "$password" = "raspberry" ] && password="-" && echo "You are not allowed to use that password."
    [ "$password" = "" ] && password="-" && echo "You can't leave the password blank."
    [ "$password" = "$password2" ] && break
    echo "Please try again"
  done

  echo ""

  # In case this is a re-initialization, delete and then re-add this user
  /bin/sed -i~ '/$username/d' /var/www/htpasswd
  echo $password | /usr/bin/htpasswd -B -c -i /var/www/htpasswd $username

  # Set the user password
  echo -e "$password\n$password" | passwd $username >$tmpdir/init 2>&1

  # Samba config
    # Change Samba User
    echo -e "$password\n$password" | smbpasswd -s -a $username
    systemctl restart smbd

if (( $(awk 'BEGIN {print ("'$ver'" >= "'1.3'")}') )); then

  # Configure NagVis user
  if (( $(awk 'BEGIN {print ("'$ver'" >= "'1.4'")}') )); then
    cp -f /root/nems/nems-migrator/data/1.4/nagvis/auth.db /etc/nagvis/etc/
  else
    cp -f /root/nems/nems-migrator/data/nagvis/auth.db /etc/nagvis/etc/
  fi
  chown www-data:www-data /etc/nagvis/etc/auth.db

  # Modify the password for NagVis
  sqlite3 /etc/nagvis/etc/auth.db "UPDATE users SET password='$(echo -n '29d58ead6a65f5c00342ae03cdc6d26565e20954'$password | sha1sum | awk '{print $1}')' WHERE name='$username'";

fi

echo "Done. You need to use your new password for NEMS Linux from now on."

fi

echo
