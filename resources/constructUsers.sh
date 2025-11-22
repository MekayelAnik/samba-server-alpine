#!/bin/bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_GUEST_ACCOUNT='guest'
readonly DEFAULT_GUEST_UID=9999
readonly DEFAULT_GUEST_GID=9999
readonly USER_UID_OFFSET=1100

log_error() {
    printf '%s: ERROR: %s\n' "$SCRIPT_NAME" "$1" >&2
}

exit_error() {
    log_error "$1"
    exit 1
}

is_valid_id() {
    [[ $1 =~ ^[0-9]+$ ]]
}

user_exists() {
    id "$1" >/dev/null 2>&1
}

create_user() {
    local user_name="$1"
    local user_pass="$2"
    local user_uid="$3"
    local user_gid="$4"

    addgroup -g "$user_gid" "$user_name" || exit_error "Failed to create group $user_name"
    adduser -D -H -u "$user_uid" -G "$user_name" "$user_name" || exit_error "Failed to create user $user_name"
    
    printf '%s\n%s\n' "$user_pass" "$user_pass" | smbpasswd -a "$user_name" || exit_error "Failed to set Samba password for $user_name"
}

validate_and_create_users() {
    local num_users="${NUMBER_OF_USERS:-0}"
    
    [[ $num_users -lt 1 ]] && return 0
    
    if ! is_valid_id "$num_users"; then
        exit_error "NUMBER_OF_USERS must be a positive integer, got: $num_users"
    fi

    for ((i = 1; i <= num_users; i++)); do
        local user_name_var="USER_NAME_${i}"
        local user_pass_var="USER_PASS_${i}"
        local user_uid_var="USER_${i}_UID"
        local user_gid_var="USER_${i}_GID"

        local user_name="${!user_name_var:-}"
        local user_pass="${!user_pass_var:-}"

        [[ -z "$user_name" || -z "$user_pass" ]] && exit_error "Missing USER_NAME_${i} or USER_PASS_${i}. Set all required variables for $num_users users."

        user_exists "$user_name" && continue

        local user_uid="${!user_uid_var:-}"
        local user_gid="${!user_gid_var:-}"

        local uid_valid=false
        local gid_valid=false

        is_valid_id "$user_uid" && uid_valid=true
        is_valid_id "$user_gid" && gid_valid=true

        case "$uid_valid:$gid_valid" in
            false:false)
                user_uid=$((USER_UID_OFFSET + i))
                user_gid=$user_uid
                ;;
            false:true)
                user_uid=$user_gid
                ;;
            true:false)
                user_gid=$user_uid
                ;;
            true:true)
                : # Both valid, use as-is
                ;;
        esac

        create_user "$user_name" "$user_pass" "$user_uid" "$user_gid"
    done
}

create_guest_user() {
    [[ ! -e /etc/samba/guest.acc ]] && return 0

    local guest_account="${GUEST_ACCOUNT:-$DEFAULT_GUEST_ACCOUNT}"
    
    user_exists "$guest_account" && { rm -f /etc/samba/guest.acc; return 0; }

    local guest_uid="${GUEST_UID:-}"
    local guest_gid="${GUEST_GID:-}"

    local uid_valid=false
    local gid_valid=false

    is_valid_id "$guest_uid" && uid_valid=true
    is_valid_id "$guest_gid" && gid_valid=true

    case "$uid_valid:$gid_valid" in
        false:false)
            guest_uid=$DEFAULT_GUEST_UID
            guest_gid=$DEFAULT_GUEST_GID
            ;;
        false:true)
            guest_uid=$guest_gid
            ;;
        true:false)
            guest_gid=$guest_uid
            ;;
        true:true)
            : # Both valid, use as-is
            ;;
    esac

    addgroup -g "$guest_gid" "$guest_account" || exit_error "Failed to create guest group"
    adduser -D -H -u "$guest_uid" -G "$guest_account" "$guest_account" || exit_error "Failed to create guest user"

    rm -f /etc/samba/guest.acc
}

main() {
    validate_and_create_users
    create_guest_user
}

main