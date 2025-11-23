#!/bin/bash
set -euo pipefail

# Color codes
readonly ORANGE='\033[38;5;208m'
readonly ERROR_RED='\033[38;5;9m'
readonly LITE_GREEN='\033[38;5;10m'
readonly NAVY_BLUE='\033[38;5;18m'
readonly GREEN='\033[38;5;2m'
readonly SEA_GREEN='\033[38;5;74m'
readonly ASH_GRAY='\033[38;5;250m'
readonly BLUE='\033[38;5;12m'
readonly NC='\033[0m'

# Configuration defaults
readonly DEBUG_MODE="${DEBUG_MODE:-0}"
readonly SMB_STATUS_UPDATE_INTERVAL="${SMB_STATUS_UPDATE_INTERVAL:-30}"
readonly BANNER_FILE="${BANNER_FILE:-/usr/bin/banner.sh}"

# State tracking
__BANNER_EXECUTED=0
__SCRIPT_SOURCES=("constructConf.sh" "constructExtraGroups.sh" "constructUsers.sh")

# Deprecation warning colors
readonly WARN_YELLOW='\033[38;5;226m'

# Error handling
error_exit() {
    printf "${ERROR_RED}Error: %s${NC}\n" "$1" >&2
    exit 1
}

log_warning() {
    printf "${WARN_YELLOW}WARNING: %s${NC}\n" "$1" >&2
}

check_deprecated_variables() {
    if [[ -n "${NUMBER_OF_SHARES:-}" ]]; then
        log_warning "NUMBER_OF_SHARES is deprecated and no longer used. Shares are now auto-discovered via SHARE_NAME_* variables."
    fi
    
    if [[ -n "${NUMBER_OF_USERS:-}" ]]; then
        log_warning "NUMBER_OF_USERS is deprecated and no longer used. Users are now auto-discovered via USER_NAME_* variables."
    fi
}

# Function to run banner.sh safely and only once
run_banner() {
    if [[ "$__BANNER_EXECUTED" -eq 1 ]]; then
        return 0
    fi

    if [[ ! -f "$BANNER_FILE" ]]; then
        printf "${ERROR_RED}Banner file not found: %s${NC}\n" "$BANNER_FILE" >&2
        return 1
    fi

    if ! bash "$BANNER_FILE"; then
        printf "${ERROR_RED}Failed to execute banner file: %s${NC}\n" "$BANNER_FILE" >&2
        return 1
    fi

    __BANNER_EXECUTED=1
    return 0
}

# Validate numeric interval
validate_interval() {
    local interval="$1"
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        error_exit "SMB_STATUS_UPDATE_INTERVAL must be numeric, got: $interval"
    fi
}

# Source required scripts
source_scripts() {
    for script in "${__SCRIPT_SOURCES[@]}"; do
        local script_path="/usr/bin/${script}"
        if [[ ! -f "$script_path" ]]; then
            error_exit "Script not found: $script_path"
        fi
        if ! source "$script_path"; then
            error_exit "Failed to source $script_path"
        fi
    done
}

# Start SMB server with status monitoring
start_server() {
    local pid=""

    # Cleanup trap
    trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi' EXIT INT TERM

    validate_interval "$SMB_STATUS_UPDATE_INTERVAL"

    source_scripts

    if ! smbd; then
        error_exit "Failed to start smbd"
    fi

    while true; do
        smbstatus
        sleep "$SMB_STATUS_UPDATE_INTERVAL" &
        pid=$!
        wait "$pid" 2>/dev/null || true
        pid=""
    done
}

# Check if debug mode is enabled
is_debug_enabled() {
    case "${DEBUG_MODE,,}" in
        yes|ye|ya|y|positive|true|t|1) return 0 ;;
        *) return 1 ;;
    esac
}

# Main entry point
main() {
    if is_debug_enabled; then
        if [[ -n "${CUSTOM_ENTRYPOINT:-}" && -x "${CUSTOM_ENTRYPOINT}" ]]; then
            printf "${ORANGE}Running custom entrypoint: %s${NC}\n" "$CUSTOM_ENTRYPOINT"
            printf "${ERROR_RED}Debug mode enabled. Custom entrypoint will be executed.${NC}\n"
            printf "${GREEN}Entering Custom Entry Point in ${NC}"
            for i in 3 2 1; do
                printf "${NAVY_BLUE}%d ${NC}" "$i"
                sleep 1
            done
            printf "\n"
            "$CUSTOM_ENTRYPOINT"
        else
            apk add nano || error_exit "Failed to install nano"
            exec sleep infinity
        fi
    else
        if ! run_banner; then
            printf "${ORANGE}Continuing despite banner execution failure${NC}\n"
        fi
        start_server
    fi
}

main "$@"