#!/bin/bash

result=$(whiptail --title "SAN Migration Utility" --menu "Choose an option" 15 150 4 \
  "Check" "Backup multipath.conf, and check the multipath.conf file from RHN to make sure it contains the 3PARdata section" \
  "Reconfigure" "Get new mulitpath.conf file, reload mulitpath, install 3PAR package, rescan the bus, and create new physical volumes on 3PAR disks" \
"Cleanup" "Remove EMC disks from the mirror and remove them from multipath" 3>&1 1>&2 2>&3)

export LVM_SUPPRESS_FD_WARNINGS=1

cluster=$(which clustat 2>&1 > /dev/null)

if [[ "$?" == 0 ]]; then
  echo " "
  echo "Warning: This tool does not yet support clusters"
  echo " "
  exit 1
fi

EMAIL=""
HOSTNAME=$(hostname)
OLDDISKS=( $(multipath -ll | grep -i symmetrix | awk '{print "/dev/mapper/"$1}') )
NEWDISKS=( $(multipath -ll | grep -i 3pardata | awk '{print "/dev/mapper/"$1}') )

Reconfigure() {
  /etc/init.d/multipathd reload
  rescan-scsi-bus.sh
  # Need to reinitialize this variable here so that it can get the 3PAR disks detected in the bus
  NEWDISKS=( $(multipath -ll | grep -i 3pardata | awk '{print "/dev/mapper/"$1}') )
  for disk in ${NEWDISKS[*]}; do
    pvcreate $disk
  done
  # Time to extend the volume groups to the new 3PAR disks Jim! This is tricky though.
  # We have to figure out the new size. How in wally's holy hell do we do that? Well,
  # The new volume can't be smaller, and it can't be ginormous.
  while IFS=',' read -r oldvg oldpv oldsize; do
    if [[ "${OLDDISKS[*]}" =~ "$oldpv" ]]; then
      while IFS=',' read -r newpv newsize; do
        if [[ "${NEWDISKS[*]}" =~ "$newpv" ]]; then
          if [[ -n "$oldvg" ]] && [[ "$newsize" == "$((oldsize+5))" ]]; then
            vgextend $oldvg $newpv
            NEWDISKS=( "${NEWDISKS[*]/$newpv}" )
            OLDDISKS=( "${OLDDISKS[*]/$oldpv}" )
            break
          fi
        fi
      done < <(pvs -o pv_name,dev_size --separator , | grep /dev/mapper | cut -d "." -f1 | tr -d " ")
    fi
  done < <(pvs -o vg_name,pv_name,dev_size --separator , | grep /dev/mapper | cut -d "." -f1 | tr -d " ")

  # We should reinitialize these variables here since we were removing paths up above.
  OLDDISKS=( $(multipath -ll | grep -i symmetrix | awk '{print "/dev/mapper/"$1}') )
  NEWDISKS=( $(multipath -ll | grep -i 3pardata | awk '{print "/dev/mapper/"$1}') )

  # Time to move the data, Jim! I know I know. This is the best part though.
  # So first we have a while loop and then an if statement checks for old disks.
  # What's that? We have an old disk, Jim? Good boy! Now start another while loop
  # inside the outer while loop to check for new disks. We have a new disk? Already?
  # You're pretty good at this. We can't move physical volumes between volume groups
  # Jim! Who do you think you are?! Now check for matching vg's and for the correct
  # size. We also need to remove the old and new pv's from our array. Why? We can't
  # use them for anything else, Jim!
  while IFS=',' read -r oldvg oldpv oldsize; do
    if [[ "${OLDDISKS[*]}" =~ "$oldpv" ]]; then
      while IFS=',' read -r newvg newpv newsize; do
        if [[ "${NEWDISKS[*]}" =~ "$newpv" ]]; then
          if [[ "$oldvg" == "$newvg" ]] && [[ "$newsize" == "$((oldsize+5))" ]]; then
            pvmove -i 20 $oldpv $newpv
            NEWDISKS=( "${NEWDISKS[*]/$newpv}" )
            OLDDISKS=( "${OLDDISKS[*]/$oldpv}" )
            break
          fi
        fi
      done < <(pvs -o vg_name,pv_name,dev_size --separator , | grep /dev/mapper | cut -d "." -f1 | tr -d " ")
    fi
  done < <(pvs -o vg_name,pv_name,dev_size --separator , | grep /dev/mapper | cut -d "." -f1 | tr -d " ")

  # We should reinitialize these variables here since we were removing paths up above.
  OLDDISKS=( $(multipath -ll | grep -i symmetrix | awk '{print "/dev/mapper/"$1}') )
  NEWDISKS=( $(multipath -ll | grep -i 3pardata | awk '{print "/dev/mapper/"$1}') )

  if [[ "$EMAIL" != '' ]]; then
    status=$(which mail 2>&1 > /dev/null)
    if [[ "$?" != 0 ]]; then
      yum install -y mailx
      echo 'Yay! Your migration is done Jim! The final step is to clean it up.' | mail -s "$HOSTNAME has finished it's migration" $EMAIL
    else
      echo 'Yay! Your migration is done Jim! The final step is to clean it up.' | mail -s "$HOSTNAME has finished it's migration" $EMAIL
    fi
  fi
}
case "$result" in
  "Check")
    if [[ -f /etc/multipath.conf ]]; then
      cp -p /etc/multipath.conf /etc/multipath.conf.$(date +%Y-%m-%d-$(whoami))
      rhncfg-client get /etc/multipath.conf
      if [[ "$?" != 0 ]]; then
        # If this failed, the ssl cert is probably wrong/old so let's try and fix it
        # insert fixins' here
        rhncfg-client get /etc/multipath.conf
      fi
      check=$(grep -i 3pardata /etc/multipath.conf)
      if [[ "$?" != 0 ]]; then
        echo "Your /etc/multipath.conf file doesn't contain the 3PARDATA section, Jim"
        exit 1
      fi
    else
      echo " "
      echo "The multipath.conf file doesn't exist Jim! Run! Run like hell!"
      echo " "
    fi
  ;;
  "Reconfigure")
    shift
    if [[ -f /etc/multipath.conf ]]; then
      # Let's make sure the bindings file is in the right place...
      if [[ -f /etc/multipath/bindings ]]; then
        Reconfigure
      else
        # Not in /etc/multipath/bindings? Okay, no problem. Let's try the next best place.
        if [[ -f /etc/bindings ]]; then
          Reconfigure
        else
          # Well Jim, this is a pretty old box. Let's copy this guy into the right place.
          if [[ -f /var/lib/multipath/bindings ]]; then
            cp -p /var/lib/multipath/bindings /etc/
            Reconfigure
          else
            echo " "
            echo "The bindings file doesn't exist Jim! Run! Run like hell!"
            echo " "
          fi
        fi
      fi
    else
      echo " "
      echo "The multipath.conf file doesn't exist Jim! Run! Run like hell!"
      echo " "
    fi
    shift
  ;;
  "Cleanup")
    shift
    while IFS=',' read -r pv size free; do
      if [[ "${OLDDISKS[*]}" =~ "$pv" ]]; then
        if [[ "$size" == "$free" ]]; then
          :
        else
          echo "$pv hasn't been moved over to 3PAR Jim!"
          setexit=$(exit 1)
        fi
      fi
    done < <(pvs -o pv_name,pv_size,pv_free --separator , | grep /dev/mapper/ | tr -d " ")

    if [[ "$?" != 0 ]]; then
      exit 1
    fi

    while IFS=',' read -r oldvg oldlv oldpv; do
      if [[ "${OLDDISKS[*]}" =~ "$oldpv" ]]; then
        if [[ -n "$oldvg" ]]; then
          vgreduce $oldvg $oldpv
        fi
      fi
    done < <(pvs -o vg_name,lv_name,pv_name --separator , | grep /dev/mapper | tr -d "[]" | tr -d " ")

    while IFS=',' read -r oldpv; do
      if [[ "${OLDDISKS[*]}" =~ "$oldpv" ]]; then
        pvremove $oldpv
      fi
    done < <(pvs -o pv_name --separator , | grep /dev/mapper | tr -d " ")

    # Need to make sure everything syncs before we try and remove the paths from multipath
    # This is to fix a bug where the a device is still being used and therefore can't be removed
    # via multipath yet
    sleep 2

    for disk in $(multipath -ll | grep -i symmetrix | awk '{print $1}'); do
      multipath -f $disk
    done

    # Just making sure everything syncs before we start removing disks
    sleep 2

    BADDISKS=( $(echo "show paths" | multipathd -k | grep -i orphan | awk '{print $2}') )

    for disk in ${BADDISKS[*]}; do
      blockdev --flushbufs $disk
      echo 1 > /sys/block/$disk/device/delete
    done
    shift
  ;;
esac
