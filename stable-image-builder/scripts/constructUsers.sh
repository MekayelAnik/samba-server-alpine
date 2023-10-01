#!/bin/bash
if [ "${NUMBER_OF_USERS}" -ge 1 ]; then
for ((i=1; i<="${NUMBER_OF_USERS}"; i++))
do
	USER_NAME=USER_NAME_${i}
	USER_PASS=USER_PASS_${i}
		if [ -z "${!USER_NAME}" ] || [ -z "${!USER_PASS}" ] ; then
    			echo "You have set NUMBER_OF_USERS to ${NUMBER_OF_USERS}"
			echo "So you have to set values in each of"
			for ((j=1; j<="${NUMBER_OF_USERS}"; j++))
			do
				echo "USER_NAME_${j}, USER_PASS_${j}"
			done
			echo "Exitting..."
		        exit 1
		fi
		if id "${!USER_NAME}" > /dev/null 2>&1; then
		        :
		else
                       	USER_UID=USER_${i}_UID
                       	USER_GID=USER_${i}_GID
			if  [[ "${!USER_UID}" =~ ^[0-9]+$ ]]; then
				U_UID=true
			elif  [[ "${!USER_GID}" =~ ^[0-9]+$ ]]; then
				U_GID=true
			else 
				U_UID=false
				U_GID=false
			fi
	                       if [ "${U_UID}" == 'false' ] && [ "${U_GID}" == 'false' ] ; then
                        	USER_UID=$(( 1100 + i ))
				USER_GID="${USER_UID}"
               			addgroup -g "${USER_GID}" "${!USER_NAME}"
	     			adduser -D -H -u "${USER_UID}" -G "${!USER_NAME}" "${!USER_NAME}"
		    		(echo "${!USER_PASS}"; echo "${!USER_PASS}") | smbpasswd -a "${!USER_NAME}"
		    	elif [ "${U_UID}" == 'false' ] && [[ "${!USER_GID}" =~ ^[0-9]+$ ]]; then
		                USER_UID="${!USER_GID}"
		                addgroup -g "${!USER_GID}" "${!USER_NAME}"
		     	        adduser -D -H -u "${USER_UID}" -G "${!USER_NAME}" "${!USER_NAME}"
		    	        (echo "${!USER_PASS}"; echo "${!USER_PASS}") | smbpasswd -a "${!USER_NAME}"
		        elif [ "${U_GID}" == 'false' ] && [[ "${!USER_UID}" =~ ^[0-9]+$ ]] ; then
		                USER_GID="${!USER_UID}" 
		                addgroup -g "${USER_GID}" "${!USER_NAME}"
		     	        adduser -D -H -u "${!USER_UID}" -G "${!USER_NAME}" "${!USER_NAME}"
	    		        (echo "${!USER_PASS}"; echo "${!USER_PASS}") | smbpasswd -a "${!USER_NAME}"
			elif [[ "${!USER_UID}" =~ ^[0-9]+$ ]] && [[ "${!USER_GID}" =~ ^[0-9]+$ ]] ; then
				addgroup -g "${!USER_GID}" "${!USER_NAME}"
			     	adduser -D -H -u "${!USER_UID}" -G "${!USER_NAME}" "${!USER_NAME}"
		    		(echo "${!USER_PASS}"; echo "${!USER_PASS}") | smbpasswd -a "${!USER_NAME}"								
			fi
		fi
done
fi

if id "${GUEST_ACCOUNT}" > /dev/null 2>&1; then
	:
else 
        if [ -n "${GUEST_ACCOUNT}" ]; then
		if  [[ "${GUEST_UID}" =~ ^[0-9]+$ ]]; then
			G_UID=true
		elif  [[ "${GUEST_GID}" =~ ^[0-9]+$ ]]; then
			G_GID=true
		else 
			G_UID=false
			G_GID=false
		fi
		if [ "${G_UID}" == 'false' ] && [ "${G_GID}" == 'false' ]; then
			GUEST_UID=9999
			GUEST_GID=9999
			addgroup -g "${GUEST_GID}" "${GUEST_NAME}"
			adduser -D -H -u "${GUEST_UID}" -G "${GUEST_NAME}" "${GUEST_NAME}"
		elif [ "${G_UID}" == 'false' ] && [[ "${GUEST_GID}"  =~ ^[0-9]+$ ]]; then
			GUEST_UID="${GUEST_GID}"
			addgroup -g "${GUEST_GID}" "${GUEST_NAME}"
			adduser -D -H -u "${GUEST_UID}" -G "${GUEST_NAME}" "${GUEST_NAME}"
		elif [[ "${GUEST_UID}" =~ ^[0-9]+$ ]] && [ "${G_GID}" == 'false' ]; then
			GUEST_GID="${GUEST_UID}"
			addgroup -g "${GUEST_GID}" "${GUEST_NAME}"
			adduser -D -H -u "${GUEST_UID}" -G "${GUEST_NAME}" "${GUEST_NAME}"
       	 	fi
	fi
fi
exit 0