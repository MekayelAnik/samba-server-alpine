#!/bin/bash
# Create Parent Directory for Samba 
for ((i=1; i<="${NUMBER_OF_SHARES}"; i++))
do
	SHARE_NAME_DIR=SHARE_NAME_${i}
	if [ -e "/data/${!SHARE_NAME_DIR}" ]; then
		:
	else mkdir -p "/data/${!SHARE_NAME_DIR}"
	fi
	SHARE_RECYCLE_BIN=SHARE_${i}_RECYCLE_BIN
	SHARE_RECYCLE_BIN=$(echo "${!SHARE_RECYCLE_BIN}" | tr '[:upper:]' '[:lower:]')
	if [ "${SHARE_RECYCLE_BIN}" == 'yes' ] || [ "${SHARE_RECYCLE_BIN}" == 'y' ] || [ "${SHARE_RECYCLE_BIN}" == 'true' ] || [ "${SHARE_RECYCLE_BIN}" == 't' ]; then
		if [ -e "/data/${!SHARE_NAME_DIR}/.recycle" ]; then
			:
		else 
			mkdir -p "/data/${!SHARE_NAME_DIR}/.recycle"
		fi
	fi
done
exit 0