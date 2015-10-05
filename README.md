# smu
SAN Migration Utility

# How to use
You can clone this repo, wget it, curl it, download the .zip, whatever. Mark smu.sh as executable by doing ```chmod +x```, and then run it like so ```./smu.sh```

This script was written to migrate from an EMC VMAX to an HP 3PAR using pvmove on RHEL 5/6 hosts. Naturally, you are going to want to modify this script to suit your needs. You'll want to modify the grep search in the OLDDISKS and NEWDISKS variables for whatever platform you're on and the one you're migrating to. I was adding 5GB to every new disk on the SAN (cause yolo), so you'll see ```"$((oldsize+5))"``` a few times. If you exported volumes that are the same size, remove that portion of the code and insert ```"$oldsize"```.

# Notes
This script assumes you're using multipath and LVM to handle your SAN disks. If you're not using even one of those things, THIS SCRIPT IS NOT FOR YOU. Also, clusters aren't supported at the moment. I'm hoping to rectify that soon.
