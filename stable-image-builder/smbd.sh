#!/bin/sh
/usr/bin/banner.sh
/usr/bin/constructUsers.sh
/usr/bin/constructDir.sh
/usr/bin/constructConf.sh
# sleep infinity
while true; do smbstatus; sleep 60 & wait; done

