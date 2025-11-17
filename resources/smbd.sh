#!/bin/bash
if [[ "${SMB_STATUS_UPDATE_INTERVAL}" =~ ^[0-9]+$ ]]; then
    INTERVAL_NUMARIC='true'
else
    INTERVAL_NUMARIC='false'
fi
if [[ -z $SMB_STATUS_UPDATE_INTERVAL ]] || [[ $INTERVAL_NUMARIC == 'false' ]]; then
    SMB_STATUS_UPDATE_INTERVAL=30
fi
bash /usr/bin/banner.sh

bash /usr/bin/constructConf.sh


bash /usr/bin/constructExtraGroups.sh
bash /usr/bin/constructUsers.sh
bash /usr/bin/constructDir.sh
smbd
while true; do smbstatus; sleep "$SMB_STATUS_UPDATE_INTERVAL" & wait; done

