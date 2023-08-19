#!/bin/bash
#===================================== GLOBAL CONFIGURATION =============================
echo "[global]" > /etc/samba/smb.conf

# Configure WORKGROUP

echo "   workgroup = "${WORKGROUP}"" >> /etc/samba/smb.conf


# Configure SERVER STRING

if [ -z "${SERVER_STRING}" ]; then
        echo "   server string = Samba Server"  >> /etc/samba/smb.conf
else
	echo "   server string = "${SERVER_STRING}"" >> /etc/samba/smb.conf
fi


# Configure SERVER MIN PROTOCOL

if [ -z "${SERVER_MIN_PROTOCOL}" ]; then
	:
else
	echo "   server min protocol = ${SERVER_MIN_PROTOCOL}" >> /etc/samba/smb.conf
fi


# Configure SERVER ROLE
	SERVER_ROLE=$(echo "${MULTI_CHANNEL_SUPPORT}" | tr '[:lower:]' '[:upper:]')
if [ -z "${SERVER_ROLE}" ] || [ "${SERVER_ROLE}" == 'AUTO' ]; then
	echo "   server role = AUTO" >> /etc/samba/smb.conf
elif [ "${SERVER_ROLE}" == 'STANDALONE' ]; then
	echo "   server role = STANDALONE" >> /etc/samba/smb.conf
elif [ "${SERVER_ROLE}" == 'MEMBER SERVER' ]; then
	echo "   server role = MEMBER SERVER" >> /etc/samba/smb.conf
elif [ "${SERVER_ROLE}" == 'CLASSIC PRIMARY DOMAIN CONTROLLER' ]; then
	echo "   server role = CLASSIC PRIMARY DOMAIN CONTROLLER" >> /etc/samba/smb.conf
elif [ "${SERVER_ROLE}" == 'ACTIVE DIRECTORY DOMAIN CONTROLLER' ]; then
	echo "   server role = ACTIVE DIRECTORY DOMAIN CONTROLLER" >> /etc/samba/smb.conf
elif [ "${SERVER_ROLE}" == 'IPA DOMAIN CONTROLLER' ]; then
	echo "   server role = IPA DOMAIN CONTROLLER" >> /etc/samba/smb.conf
else :
fi

# Enable/Disable  MULTI CHANNEL SPEED AGGRAGATION
MULTI_CHANNEL_SUPPORT=$(echo "${MULTI_CHANNEL_SUPPORT}" | tr '[:upper:]' '[:lower:]')
	if [ "${MULTI_CHANNEL_SUPPORT}" == 'yes' ] || [ "${MULTI_CHANNEL_SUPPORT}" == 'ye' ] || [ "${MULTI_CHANNEL_SUPPORT}" == 't' ] || [ "${MULTI_CHANNEL_SUPPORT}" == 'y' ] || [ "${MULTI_CHANNEL_SUPPORT}" == 'true' ]; then
		MULTI_CHANNEL_SUPPORT=yes
		echo "   server multi channel support = ${MULTI_CHANNEL_SUPPORT}" >> /etc/samba/smb.conf
		echo "   aio read size = 1" >> /etc/samba/smb.conf
		echo "   aio write size = 1" >> /etc/samba/smb.conf
	else
	        MULTI_CHANNEL_SUPPORT=no
		echo "   server multi channel support = ${MULTI_CHANNEL_SUPPORT}" >> /etc/samba/smb.conf
	fi
	
# Configure Allowed CLIENTS to the Server

if [ -z "${ALLOWED_HOSTS}" ]; then
	echo ";  hosts allow = 192.168.1. 192.168.2. 127." >> /etc/samba/smb.conf

elif [ -n "${ALLOWED_HOSTS}" ]; then 
	echo "   hosts allow = $ALLOWED_HOSTS" >> /etc/samba/smb.conf
fi


# Enable/Disable  NETBIOS

DISABLE_NETBIOS=$(echo "${DISABLE_NETBIOS}" | tr '[:upper:]' '[:lower:]')
if [ "${DISABLE_NETBIOS}" == 'yes' ] || [ "${DISABLE_NETBIOS}" == 'y' ] || [ "${DISABLE_NETBIOS}" == 'true' ] || [ "${DISABLE_NETBIOS}" == 't' ] || [ "${DISABLE_NETBIOS}" == 'ye' ]; then
	DISABLE_NETBIOS=yes
	echo "   disable netbios = "${DISABLE_NETBIOS}"" >> /etc/samba/smb.conf
else 
	DISABLE_NETBIOS=no
	echo "   disable netbios = "${DISABLE_NETBIOS}"" >> /etc/samba/smb.conf

fi

#===================================== SERVER PORTS =============================
# Configure NETBIOS PORT

if  [[ "${NETBIOS_PORT}" =~ ^[0-9]+$ ]]; then 
	:
else 
	NETBIOS_PORT=139
fi


# Configure SMB CONNECTION PORT

if  [[ "${SMB_PORT}" =~ ^[0-9]+$ ]]; then 
	:
else 
	SMB_PORT=445
fi

if [ "${DISABLE_NETBIOS}" == 'yes' ]; then 
	echo "   smb ports = "${SMB_PORT}"" >> /etc/samba/smb.conf
elif [[ "${DISABLE_NETBIOS}" == 'no' ]]; then 
	echo "   smb ports = "${SMB_PORT}" "${NETBIOS_PORT}"" >> /etc/samba/smb.conf
fi


# MAP to GUESTS

MAP_TO_GUEST=$(echo "${MAP_TO_GUEST}" | tr '[:upper:]' '[:lower:]')
if [ -z "${MAP_TO_GUEST}" ]; then
	:
elif [ "${MAP_TO_GUEST}" == 'bad user' ] ||  [ "${MAP_TO_GUEST}" == 'baduser' ] ; then 
	MAP_TO_GUEST=Bad User
	echo "   map to guest = "${MAP_TO_GUEST}"" >> /etc/samba/smb.conf
elif [ "${MAP_TO_GUEST}" == 'bad password' ] ||  [ "${MAP_TO_GUEST}" == 'badpassword' ]; then
	MAP_TO_GUEST=Bad Password
	echo "   map to guest = "${MAP_TO_GUEST}"" >> /etc/samba/smb.conf
fi


# Mapping Guests to GUEST ACCOUNT

if [ -n "${GUEST_ACCOUNT}" ]; then 
	echo "   guest account = $GUEST_ACCOUNT" >> /etc/samba/smb.conf
fi

# Log File Location
echo "   log file = /usr/local/samba/var/log.%m" >> /etc/samba/smb.conf


# Configure Log File Size

if [[ "${MAX_LOG_SIZE}" =~ ^[0-9]+$ ]]; then
    echo "   max log size = $MAX_LOG_SIZE" >> /etc/samba/smb.conf
else
    echo "   max log size = 50" >> /etc/samba/smb.conf
fi

# Configure DNS Proxy

DNS_PROXY=$(echo "${DNS_PROXY}" | tr '[:upper:]' '[:lower:]')
if [ "${DNS_PROXY}" == 'yes' ] || [ "${DNS_PROXY}" == 'y' ] ||  [ "${DNS_PROXY}" == 'true' ] || [ "${DNS_PROXY}" == 't' ]; then
	DNS_PROXY=yes	
else
	DNS_PROXY=no
fi
echo "   dns proxy = $DNS_PROXY" >> /etc/samba/smb.conf

echo "#============================ SHARE DEFINATIONS ==============================" >> /etc/samba/smb.conf
if [ "${NUMBER_OF_SHARES}" -ge 1 ]; then
	for ((i=1; i<="${NUMBER_OF_SHARES}"; i++))
	do
		SHARE_NAME=SHARE_NAME_${i}
		SHARE_GUEST_ONLY=SHARE_${i}_GUEST_ONLY
		SHARE_WRITEABLE=SHARE_${i}_WRITEABLE
		SHARE_WRITE_LIST=SHARE_${i}_WRITE_LIST
		SHARE_READ_ONLY=SHARE_${i}_READ_ONLY
		SHARE_READ_LIST=SHARE_${i}_READ_LIST
		SHARE_BROWSEABLE=SHARE_${i}_BROWSEABLE
		SHARE_VALID_USERS=SHARE_${i}_VALID_USERS
		SHARE_PUBLIC=SHARE_${i}_PUBLIC
		SHARE_GUEST_OK=SHARE_${i}_GUEST_OK
		SHARE_CREATE_MASK=SHARE_${i}_CREATE_MASK
		SHARE_DIRECTORY_MASK=SHARE_${i}_DIRECTORY_MASK
		SHARE_DIRECTORY_MODE=SHARE_${i}_DIRECTORY_MODE
		SHARE_FORCE_USER=SHARE_${i}_FORCE_USER
		SHARE_FORCE_GROUP=SHARE_${i}_FORCE_GROUP
		SHARE_COMMENT=SHARE_${i}_COMMENT
		SHARE_RECYCLE_BIN=SHARE_${i}_RECYCLE_BIN
		RECYCLE_MAX_SIZE=SHARE_${i}_RECYCLE_MAX_SIZE
		RECYCLE_MIN_SIZE=SHARE_${i}_RECYCLE_MIN_SIZE
		RECYCLE_DIRECTORY_MODE=SHARE_${i}_RECYCLE_DIRECTORY_MODE
echo "#============================ CONFIGURATION FOR NAS STARTS HERE ============================" >> /etc/samba/smb.conf
echo ""
echo "#============================ CONFIGURATION FOR USER SHARE: [${!SHARE_NAME}] ============================" >> /etc/samba/smb.conf

# Configure SHARE NAME 
			if [ -z "${!SHARE_NAME}" ]; then
				echo "You have set the value of  NUMBER_OF_SHARES environtment to $NUMBER_OF_SHARES. So you have to set all of:"
				for ((j=1; j<="${NUMBER_OF_SHARES}"; j++))
				do
					echo "SHARE_NAME_${j}"
				done
				echo "Exiting..."
				exit 1
			fi
echo "[${!SHARE_NAME}]" >> /etc/samba/smb.conf

# Configure SHARE COMMENT
			if [ -z "${!SHARE_COMMENT}" ]; then
				:
			else
				echo "   comment = ${!SHARE_COMMENT}" >> /etc/samba/smb.conf
			fi

# Configure SHARE PATH
echo "   path = /data/${!SHARE_NAME}" >> /etc/samba/smb.conf

# Configure  VALID-USERS  
			if [ -z "${!SHARE_VALID_USERS}" ]; then
				:
			else
				echo "   valid users = ${!SHARE_VALID_USERS}" >> /etc/samba/smb.conf
			fi
			
# Configure PUBLIC and GUEST OK
			SHARE_GUEST_OK=$(echo "${!SHARE_GUEST_OK}" | tr '[:upper:]' '[:lower:]')
			SHARE_PUBLIC=$(echo "${!SHARE_PUBLIC}" | tr '[:upper:]' '[:lower:]')
			if [ "${SHARE_GUEST_OK}" == 'yes' ] || [ "${SHARE_GUEST_OK}" == 'y' ] || [ "${SHARE_GUEST_OK}" == 'ye' ] || [ "${SHARE_GUEST_OK}" == 'true' ] || [ "${SHARE_GUEST_OK}" == 't' ]; then
  				SHARE_PUBLIC=yes
			elif [ "${SHARE_PUBLIC}" == 'yes' ] || [ "${SHARE_PUBLIC}" == 'y' ] || [ "${SHARE_PUBLIC}" == 'ye' ] || [ "${SHARE_PUBLIC}" == 'true' ] || [ "${SHARE_PUBLIC}" == 't' ]; then
				SHARE_PUBLIC=yes
			else SHARE_PUBLIC=no	
			fi
			echo "   public = ${SHARE_PUBLIC}" >> /etc/samba/smb.conf
			
# Configure GUEST ONLY
			SHARE_GUEST_ONLY=$(echo "${!SHARE_GUEST_ONLY}" | tr '[:upper:]' '[:lower:]')
			if [ "${SHARE_GUEST_ONLY}" == 'yes' ] || [ "${SHARE_GUEST_ONLY}" == 'y' ] || [ "${SHARE_GUEST_ONLY}" == 'true' ] || [ "${SHARE_GUEST_ONLY}" == 't' ] && [ -z "${!SHARE_VALID_USERS}" ]; then
				SHARE_GUEST_ONLY=yes
				SHARE_PUBLIC=yes
			else 
				SHARE_GUEST_ONLY=no
			fi
			echo "   guest only = ${SHARE_GUEST_ONLY}" >> /etc/samba/smb.conf

# Configure BROWSABLE
			SHARE_BROWSEABLE=$(echo "${!SHARE_BROWSEABLE}" | tr '[:upper:]' '[:lower:]')
			if [ "${SHARE_BROWSEABLE}" == 'no' ] || [ "${SHARE_BROWSEABLE}" == 'n' ] || [ "${SHARE_BROWSEABLE}" == 'false' ] || [ "${SHARE_BROWSEABLE}" == 'f' ]; then
				SHARE_BROWSEABLE=no
			else 
				SHARE_BROWSEABLE=yes
			fi
			echo "   browseable = ${SHARE_BROWSEABLE}" >> /etc/samba/smb.conf
			
# Configure READ-ONLY and WRITABLE
			SHARE_READ_ONLY=$(echo "${!SHARE_READ_ONLY}" | tr '[:upper:]' '[:lower:]')
			SHARE_WRITEABLE=$(echo "${!SHARE_WRITEABLE}" | tr '[:upper:]' '[:lower:]')
			if [ "${SHARE_READ_ONLY}" == 'no' ] || [ "${SHARE_READ_ONLY}" == 'n' ] || [ "${SHARE_READ_ONLY}" == 'false' ] || [ "${SHARE_READ_ONLY}" == 'f' ]; then
				SHARE_WRITEABLE=yes
			elif [ "${SHARE_WRITEABLE}" == 'yes' ] || [ "${SHARE_WRITEABLE}" == 'y' ] || [ "${SHARE_WRITEABLE}" == 'true' ] || [ "${SHARE_WRITEABLE}" == 't' ]; then
				SHARE_WRITEABLE=yes
			else SHARE_WRITEABLE=no
			fi
			echo "   writable = ${SHARE_WRITEABLE}" >> /etc/samba/smb.conf
			
#  Configure READ-LIST
			if [ -z "${!SHARE_READ_LIST}" ]; then
				:
			else
				echo "   read list = ${!SHARE_READ_LIST}" >> /etc/samba/smb.conf
			fi
			
#  Configure WRITE-LIST
			if [ -z "${!SHARE_WRITE_LIST}" ]; then
				:
			else
				echo "   write list = ${!SHARE_WRITE_LIST}" >> /etc/samba/smb.conf
			fi
			
# Settings for CREATE-MASK
			if  [[ "${!SHARE_CREATE_MASK}" =~ ^[0-9]+$ ]]; then 
				echo "   create mask = ${!SHARE_CREATE_MASK}" >> /etc/samba/smb.conf
			else 
				:
			fi

# Settings for DIRECTORY-MASK
			if  [[ "${!SHARE_DIRECTORY_MASK}" =~ ^[0-9]+$ ]]; then 
				echo "   directory mask = ${!SHARE_DIRECTORY_MASK}" >> /etc/samba/smb.conf
			elif [[ "${!SHARE_DIRECTORY_MODE}" =~ ^[0-9]+$ ]] && [ -z "${!SHARE_DIRECTORY_MASK}" ]; then
				echo "   directory mask = ${!SHARE_DIRECTORY_MODE}" >> /etc/samba/smb.conf
			else 
				:
			fi
			
# Settings for FORCE-USER
			if [ -z "${!SHARE_FORCE_USER}" ]; then
				:
			else
				echo "   force user = ${!SHARE_FORCE_USER}" >> /etc/samba/smb.conf
			fi
			
# Settings for FORCE-GROUP
			if [ -z "${!SHARE_FORCE_GROUP}" ]; then
				:
			else
				echo "   force group = ${!SHARE_FORCE_GROUP}" >> /etc/samba/smb.conf
			fi

# ENABLE/DISABLE RECYCLE-BIN
	SHARE_RECYCLE_BIN=$(echo "${!SHARE_RECYCLE_BIN}" | tr '[:upper:]' '[:lower:]')
			if [ "${SHARE_RECYCLE_BIN}" == 'yes' ] || [ "${SHARE_RECYCLE_BIN}" == 'y' ] || [ "${SHARE_RECYCLE_BIN}" == 'true' ] || [ "${SHARE_RECYCLE_BIN}" == 't' ]; then
				echo "   vfs object = recycle" >> /etc/samba/smb.conf
				echo "   recycle:repository = /data/${!SHARE_NAME}/.recycle/%U" >> /etc/samba/smb.conf
				echo "   recycle:keeptree = yes" >> /etc/samba/smb.conf
				echo "   recycle:versions = yes" >> /etc/samba/smb.conf
				echo "   recycle:touch = yes" >> /etc/samba/smb.conf
				echo "   recylce:exclude_dir = /tmp /TMP /temp /TEMP /public /cache /CACHE" >> /etc/samba/smb.conf
				echo "   recycle:exclude = *.TMP *.tmp *.temp ~$* *.log *.bak" >> /etc/samba/smb.conf
				if [ -z "${!RECYCLE_DIRECTORY_MODE}" ]; then
					:
				else 
					if  [[ "${!RECYCLE_DIRECTORY_MODE}" =~ ^[0-9]+$ ]]; then
					        echo "   recycle:directory_mode = "${!RECYCLE_DIRECTORY_MODE}"" >> /etc/samba/smb.conf
				        else
					        :
				        fi
				fi
				if  [[ "${!RECYCLE_MAX_SIZE}" =~ ^[0-9]+$ ]]; then
					echo "   recycle:maxsize = "${!RECYCLE_MAX_SIZE}"" >> /etc/samba/smb.conf
				else
					:
				fi
				if  [[ "${!RECYCLE_MIN_SIZE}" =~ ^[0-9]+$ ]]; then
					echo "   recycle:minsize= "${!RECYCLE_MIN_SIZE}"" >> /etc/samba/smb.conf
				else
					:
				fi
			else
				:
			fi	
	done
fi
echo ""  >> /etc/samba/smb.conf
echo "#============================ CONFIGURATION FOR USER SHARES ENDS HERE ============================" >> /etc/samba/smb.conf
echo "" >> /etc/samba/smb.conf


# ENABLE/DISABLE TEMP SHARE
TEMP_SHARE_ON=$(echo "${TEMP_SHARE_ON}" | tr '[:upper:]' '[:lower:]')
if [ "${TEMP_SHARE_ON}" == 'yes' ] || [ "${TEMP_SHARE_ON}" == 'y' ] || [ "${TEMP_SHARE_ON}" == 'true' ] || [ "${TEMP_SHARE_ON}" == 't' ] || [ "${TEMP_SHARE_ON}" == 'ye' ]; then
echo "#============================ CONFIGURATION FOR: TEMP SHARE (GROUND FOR PUBLIC DATA EXCHANGE) ============================" >> /etc/samba/smb.conf
if [ -z "${TEMP_SHARE_NAME}" ]; then
	TEMP_SHARE_NAME=temp-share
else
	:
fi
echo "["${TEMP_SHARE_NAME}"]"  >> /etc/samba/smb.conf
echo "   path = /data/${TEMP_SHARE_NAME}"  >> /etc/samba/smb.conf
			if [ -z "${TEMP_SHARE_COMMENT}" ]; then
				:
			else
				echo "   comment = ${TEMP_SHARE_COMMENT}" >> /etc/samba/smb.conf
			fi

# CONFIGURE TEMP SHARE READ-ONLY
if [ -z "${TEMP_SHARE_READ_ONLY}" ]; then
	TEMP_SHARE_READ_ONLY=no
else
	:
fi
TEMP_SHARE_READ_ONLY=$(echo "${TEMP_SHARE_READ_ONLY}" | tr '[:upper:]' '[:lower:]')
if [ "${TEMP_SHARE_READ_ONLY}" == 'yes' ] || [ "${TEMP_SHARE_READ_ONLY}" == 'y' ] || [ "${TEMP_SHARE_READ_ONLY}" == 'true' ] || [ "${TEMP_SHARE_READ_ONLY}" == 't' ] || [ "${TEMP_SHARE_READ_ONLY}" == 'ye' ] || [ "${TEMP_SHARE_WRITABLE}" == 'no' ] || [ "${TEMP_SHARE_WRITABLE}" == 'n' ] || [ "${TEMP_SHARE_WRITABLE}" == 'false' ] || [ "${TEMP_SHARE_WRITABLE}" == 'f' ]; then			
	TEMP_SHARE_READ_ONLY=yes
	echo "   read only = "${TEMP_SHARE_READ_ONLY}""  >> /etc/samba/smb.conf
else 
	TEMP_SHARE_READ_ONLY=no
	echo "   read only = "${TEMP_SHARE_READ_ONLY}""  >> /etc/samba/smb.conf
fi

# CONFIGURE TEMP SHARE PUBLIC 
if [ -z "${TEMP_SHARE_PUBLIC}" ]; then
	TEMP_SHARE_PUBLIC=yes
else
	:
fi
TEMP_SHARE_PUBLIC=$(echo "${TEMP_SHARE_PUBLIC}" | tr '[:upper:]' '[:lower:]')
if [ "${TEMP_SHARE_PUBLIC}" == 'no' ] || [ "${TEMP_SHARE_PUBLIC}" == 'n' ] || [ "${TEMP_SHARE_PUBLIC}" == 'false' ] || [ "${TEMP_SHARE_PUBLIC}" == 'f' ] || [ "${TEMP_SHARE_GUEST_OK}" == 'no' ] || [ "${TEMP_SHARE_GUEST_OK}" == 'n' ] || [ "${TEMP_SHARE_GUEST_OK}" == 'false' ] || [ "${TEMP_SHARE_GUEST_OK}" == 'f' ]; then			
        TEMP_SHARE_PUBLIC=no
        echo echo "   public = "${TEMP_SHARE_PUBLIC}""  >> /etc/samba/smb.conf
else 
        TEMP_SHARE_PUBLIC=yes
        echo "   public = "${TEMP_SHARE_PUBLIC}""  >> /etc/samba/smb.conf
fi

# ENABLE/DISABLE TEM SHARE RECYCLE-BIN
	TEMP_RECYCLE_BIN=$(echo "${TEMP_RECYCLE_BIN}" | tr '[:upper:]' '[:lower:]')
			if [ "${TEMP_RECYCLE_BIN}" == 'yes' ] || [ "${TEMP_RECYCLE_BIN}" == 'y' ] || [ "${TEMP_RECYCLE_BIN}" == 'true' ] || [ "${TEMP_RECYCLE_BIN}" == 't' ]; then
				echo "   vfs object = recycle" >> /etc/samba/smb.conf
				echo "   recycle:repository = /data/${TEMP_SHARE_NAME}/.recycle/%U" >> /etc/samba/smb.conf
				echo "   recycle:keeptree = yes" >> /etc/samba/smb.conf
				echo "   recycle:versions = yes" >> /etc/samba/smb.conf
				echo "   recycle:touch = yes" >> /etc/samba/smb.conf
				echo "   recylce:exclude_dir = /tmp /TMP /temp /TEMP /public /cache /CACHE" >> /etc/samba/smb.conf
				echo "   recycle:exclude = *.TMP *.tmp *.temp ~$* *.log *.bak" >> /etc/samba/smb.conf
				if [ -z "${TEMP_RECYCLE_DIRECTORY_MODE}" ]; then
					:
				else 
					if  [[ "${TEMP_RECYCLE_DIRECTORY_MODE}" =~ ^[0-9]+$ ]]; then
						echo "   recycle:directory_mode = "${TEMP_RECYCLE_DIRECTORY_MODE}"" >> /etc/samba/smb.conf
					else
						:
					fi

				fi
				if  [[ "${TEMP_RECYCLE_MAX_SIZE}" =~ ^[0-9]+$ ]]; then
					echo "   recycle:maxsize = "${TEMP_RECYCLE_MAX_SIZE}"" >> /etc/samba/smb.conf
				else
					:
				fi
				if  [[ "${TEMP_RECYCLE_MIN_SIZE}" =~ ^[0-9]+$ ]]; then
					echo "   recycle:minsize= "${TEMP_RECYCLE_MIN_SIZE}"" >> /etc/samba/smb.conf
				else
					:
				fi
			else
				:
			fi

echo ""  >> /etc/samba/smb.conf
echo "#============================ CONFIGURATION FOR TEMP SHARE ENDS HERE ============================" >> /etc/samba/smb.conf
fi
echo "#============================ CONFIGURATION FOR NAS ENDS HERE ============================" >> /etc/samba/smb.conf
exit 0