#!/bin/bash
set -euo pipefail
# Standard colors mapped to 8-bit equivalents
readonly ORANGE='\033[38;5;208m'
readonly ERROR_RED='\033[38;5;9m'
readonly LITE_GREEN='\033[38;5;10m'
readonly NAVY_BLUE='\033[38;5;18m'
readonly GREEN='\033[38;5;2m'
readonly SEA_GREEN='\033[38;5;74m'
readonly ASH_GRAY='\033[38;5;250m'
readonly BLUE='\033[38;5;12m'
readonly NC='\033[0m'

__BANNER_EXECUTED=0


# Function to run banner.sh safely and only once
run_banner() {
    BANNER_FILE=${SMB_STATUS_UPDATE_INTERVAL:-"/usr/bin/banner.sh"}
    if [[ "$__BANNER_EXECUTED" -ne 1 ]]; then
        if [[ -f "$BANNER_FILE" ]]; then
            if ! bash "$BANNER_FILE"; then
                printf "${ERROR_RED}Failed to execute banner file: %s${NC}\n" "$BANNER_FILE" >&2
                return 1
            fi
            __BANNER_EXECUTED=1
        else
            printf "${ERROR_RED}Banner file not found: %s${NC}\n" "$BANNER_FILE" >&2
            return 1
        fi
    fi
    return 0
}


start_server() {

PID=""

trap 'if [ -n "$PID" ]; then kill $PID 2>/dev/null || true; fi' EXIT INT TERM

readonly INTERVAL="$(( ${SMB_STATUS_UPDATE_INTERVAL:-30} ))" 2>/dev/null || { echo "Error: SMB_STATUS_UPDATE_INTERVAL must be numeric" >&2; exit 1; }

for script in constructConf.sh constructExtraGroups.sh constructUsers.sh; do
    source "/usr/bin/${script}" || { echo "Error: Failed to source ${script}" >&2; exit 1; }
done

smbd || { echo "Error: Failed to start smbd" >&2; exit 1; }

while true; do
    smbstatus
    sleep "${INTERVAL}" &
    PID=$!
    wait "${PID}" 2>/dev/null || true
    PID=""
done

}

main () {
    case "${DEBUG_MODE,,}" in
        yes|ye|ya|y|positive|true|t|1)
            # Run banner immediately at script start
            if [[ -n "${CUSTOM_ENTRYPOINT:-}" && -x "${CUSTOM_ENTRYPOINT:-}" ]]; then
                chmod +x "$CUSTOM_ENTRYPOINT" || error_exit "Failed to set execute permissions for custom entrypoint"
                printf "${ORANGE}Running custom entrypoint: %s${NC}\n" "$CUSTOM_ENTRYPOINT"
                printf "${ERROR_RED}Debug mode enabled. Custom entrypoint will be executed.${NC}\n"
                printf "${GREEN}Entering Custom Entry Point in ${NC}"
                for i in 3 2 1; do
                    printf "${NAVY_BLUE}%d ${NC}" "$i"
                    sleep 1
                done
                printf "\r\n"
                export DEBUG_MODE="false"
            else
                apk add nano || error_exit "Failed to install nano"
                exec sleep infinity
            fi
            ;;
        *)
            if ! run_banner; then
                printf "${ORANGE}Continuing despite banner execution failure${NC}\n"
            fi
            start_server
            ;;
    esac
}

main