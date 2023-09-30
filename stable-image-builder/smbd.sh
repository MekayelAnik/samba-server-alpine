#!/bin/bash
bash /usr/bin/banner.sh
bash /usr/bin/constructUsers.sh
bash /usr/bin/constructDir.sh
bash /usr/bin/constructConf.sh
smbd
while true; do smbstatus; sleep 60 & wait; done

