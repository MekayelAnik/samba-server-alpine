#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

readonly SMB_CONF="/etc/samba/smb.conf"
readonly GUEST_ACC="/etc/samba/guest.acc"
readonly DATA_DIR="/data"

log_error() {
    echo "[ERROR] $*" >&2
}

validate_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

normalize_bool() {
    local val="${1,,}"
    case "$val" in
        yes|y|ye|true|t|1) echo "yes" ;;
        no|n|false|f|0) echo "no" ;;
        *) echo "${2:-no}" ;;
    esac
}

write_conf() {
    printf '%s\n' "$1" >> "$SMB_CONF"
}

get_share_indices() {
    compgen -v SHARE_NAME_ 2>/dev/null | sed 's/SHARE_NAME_//' || true
}

create_share_directories() {
    local share_indices
    share_indices=$(get_share_indices)
    
    [[ -z "$share_indices" ]] && return
    
    while IFS= read -r i; do
        local share_name_var="SHARE_NAME_$i"
        local share_name="${!share_name_var:-}"
        
        [[ -z "$share_name" ]] && continue
        
        local share_path="$DATA_DIR/$share_name"
        [[ ! -e "$share_path" ]] && mkdir -p "$share_path"
        
        local recycle_var="SHARE_${i}_RECYCLE_BIN"
        local recycle
        recycle=$(normalize_bool "${!recycle_var:-no}" "no")
        
        if [[ "$recycle" == "yes" ]]; then
            local recycle_path="$share_path/.recycle"
            [[ ! -e "$recycle_path" ]] && mkdir -p "$recycle_path"
        fi
    done <<< "$share_indices"
    
    local temp_on
    temp_on=$(normalize_bool "${TEMP_SHARE_ON:-no}" "no")
    
    if [[ "$temp_on" == "yes" ]]; then
        local temp_name="${TEMP_SHARE_NAME:-temp-share}"
        local temp_path="$DATA_DIR/$temp_name"
        [[ ! -e "$temp_path" ]] && mkdir -p "$temp_path"
        
        local temp_recycle
        temp_recycle=$(normalize_bool "${TEMP_RECYCLE_BIN:-no}" "no")
        
        if [[ "$temp_recycle" == "yes" ]]; then
            local temp_recycle_path="$temp_path/.recycle"
            [[ ! -e "$temp_recycle_path" ]] && mkdir -p "$temp_recycle_path"
        fi
    fi
}

global_config() {
    cat > "$SMB_CONF" << 'EOF'
[global]
EOF

    write_conf "   log level = ${SMB_LOG_LEVEL:-1}"
    write_conf "   log file = /usr/local/samba/var/log.%m"
    write_conf "   max log size = ${MAX_LOG_SIZE:-50}"
    write_conf "   deadtime = ${SMB_DEADTIME:-15}"
    write_conf "   max open files = ${SMB_MAX_OPEN_FILES:-30000}"

    write_conf "   workgroup = ${SMB_WORKGROUP:-WORKGROUP}"
    write_conf "   server string = ${SERVER_STRING:-Samba Server}"
    write_conf "   server min protocol = ${SERVER_MIN_PROTOCOL:-SMB2}"

    local role="${SERVER_ROLE:-AUTO}"
    role="${role^^}"
    case "$role" in
        STANDALONE|"MEMBER SERVER"|"CLASSIC PRIMARY DOMAIN CONTROLLER"|"ACTIVE DIRECTORY DOMAIN CONTROLLER"|"IPA DOMAIN CONTROLLER")
            write_conf "   server role = $role"
            ;;
        *)
            write_conf "   server role = AUTO"
            ;;
    esac

    local multi_channel
    multi_channel=$(normalize_bool "${MULTI_CHANNEL_SUPPORT:-no}" "no")
    write_conf "   server multi channel support = $multi_channel"

    write_conf "   socket options = ${SOCKET_OPTIONS:-TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE}"

    local dns_proxy
    dns_proxy=$(normalize_bool "${DNS_PROXY:-no}" "no")
    write_conf "   dns proxy = $dns_proxy"

    write_conf "   use sendfile = yes"
    write_conf "   min receivefile size = ${SMB_MIN_RECEIVEFILE_SIZE:-16384}"
    write_conf "   aio read size = 1"
    write_conf "   aio write size = 1"

    local strict_locking oplocks level2_oplocks
    strict_locking=$(normalize_bool "${SMB_STRICT_LOCKING:-no}" "no")
    oplocks=$(normalize_bool "${SMB_OPLOCKS:-yes}" "yes")
    level2_oplocks=$(normalize_bool "${SMB_LEVEL2_OPLOCKS:-yes}" "yes")
    write_conf "   strict locking = $strict_locking"
    write_conf "   oplocks = $oplocks"
    write_conf "   level2 oplocks = $level2_oplocks"

    if [[ -n "${ALLOWED_HOSTS:-}" ]]; then
        write_conf "   hosts allow = $ALLOWED_HOSTS"
    else
        write_conf ";  hosts allow = 127. 10. 172.16. 192.168."
    fi

    local encrypt="${GLOBAL_ENCRYPT:-auto}"
    encrypt="${encrypt,,}"
    case "$encrypt" in
        required|enable|enabled|yes|ok|y|mandatory|ya|1) encrypt="required" ;;
        disable|d|off|no|n|0) encrypt="disabled" ;;
        *) encrypt="auto" ;;
    esac
    GLOBAL_ENCRYPT="$encrypt"
    write_conf "   server smb encrypt = $encrypt"

    local disable_netbios netbios_port smb_port
    disable_netbios=$(normalize_bool "${DISABLE_NETBIOS:-no}" "no")
    netbios_port="${NETBIOS_PORT:-139}"
    smb_port="${SMB_PORT:-445}"
    
    validate_numeric "$netbios_port" || netbios_port=139
    validate_numeric "$smb_port" || smb_port=445
    
    write_conf "   disable netbios = $disable_netbios"
    if [[ "$disable_netbios" == "yes" ]]; then
        write_conf "   smb ports = $smb_port"
    else
        write_conf "   smb ports = $smb_port $netbios_port"
    fi

    local map_to_guest="${MAP_TO_GUEST:-}"
    map_to_guest="${map_to_guest,,}"
    case "$map_to_guest" in
        "bad user"|baduser) write_conf "   map to guest = Bad User" ;;
        "bad password"|badpassword) write_conf "   map to guest = Bad Password" ;;
    esac

    if [[ -e "$GUEST_ACC" ]]; then
        write_conf "   guest account = ${GUEST_ACCOUNT:-guest}"
    fi

    write_conf "   unix extensions = yes"
    write_conf "   wide links = no"
    write_conf "   create mask = 0777"
    write_conf "   directory mask = 0777"

    local macos_opts
    macos_opts=$(normalize_bool "${ENABLE_MACOS_OPTS:-yes}" "yes")
    
    if [[ "$macos_opts" == "yes" ]]; then
        BASE_VFS_MODULES="catia fruit streams_xattr"
        write_conf "   # Special configuration for Apple's Time Machine & Performance"
        write_conf "   fruit:aapl = yes"
        write_conf "   fruit:copyfile = yes"
        write_conf "   fruit:nfs_aces = no"
        write_conf "   fruit:metadata = stream"
        write_conf "   fruit:model = MacSamba"
        write_conf "   fruit:posix_rename = yes"
        write_conf "   fruit:veto_appledouble = no"
        write_conf "   fruit:wipe_intentionally_left_blank_rfork = yes"
        write_conf "   fruit:delete_empty_adfiles = yes"
    else
        BASE_VFS_MODULES=""
    fi
}

enable_guest_account() {
    [[ -e "$GUEST_ACC" ]] || touch "$GUEST_ACC"
}

configure_share() {
    local i=$1
    local share_name_var="SHARE_NAME_$i"
    local share_name="${!share_name_var:-}"

    if [[ -z "$share_name" ]]; then
        log_error "SHARE_NAME_$i is not set"
        return 1
    fi

    write_conf ""
    write_conf "#============================ CONFIGURATION FOR USER SHARE: [$share_name] ============================"
    write_conf "[$share_name]"

    local comment_var="SHARE_${i}_COMMENT"
    [[ -n "${!comment_var:-}" ]] && write_conf "   comment = ${!comment_var}"

    write_conf "   path = $DATA_DIR/$share_name"

    if [[ "${GLOBAL_ENCRYPT:-auto}" == "auto" ]]; then
        local encrypt_var="SHARE_${i}_ENCRYPT"
        local share_encrypt="${!encrypt_var:-auto}"
        share_encrypt="${share_encrypt,,}"
        case "$share_encrypt" in
            required|require|mandatory|enabled|enable|yes|ok|y|ya|1) share_encrypt="required" ;;
            disable|d|off|no|n|disabled|0) share_encrypt="disabled" ;;
            *) share_encrypt="auto" ;;
        esac
        write_conf "   server smb encrypt = $share_encrypt"
    fi

    local ea_var="SHARE_${i}_ENABLE_EXTENDED_ATTRIBUTE"
    local ea
    ea=$(normalize_bool "${!ea_var:-yes}" "yes")
    write_conf "   ea support = $ea"

    local dos_var="SHARE_${i}_ENABLE_DOS_ATTRIBUTE"
    local dos_attr
    dos_attr=$(normalize_bool "${!dos_var:-yes}" "yes")
    write_conf "   store dos attributes = $dos_attr"

    local valid_users_var="SHARE_${i}_VALID_USERS"
    [[ -n "${!valid_users_var:-}" ]] && write_conf "   valid users = ${!valid_users_var}"

    local guest_ok_var="SHARE_${i}_GUEST_OK"
    local public_var="SHARE_${i}_PUBLIC"
    local guest_ok
    guest_ok=$(normalize_bool "${!guest_ok_var:-no}" "no")
    local public
    public=$(normalize_bool "${!public_var:-no}" "no")

    if [[ "$guest_ok" == "yes" ]]; then
        public="yes"
        enable_guest_account
    fi
    write_conf "   public = $public"

    local guest_only_var="SHARE_${i}_GUEST_ONLY"
    local guest_only
    guest_only=$(normalize_bool "${!guest_only_var:-no}" "no")
    
    if [[ "$guest_only" == "yes" && -z "${!valid_users_var:-}" ]]; then
        enable_guest_account
    else
        guest_only="no"
    fi
    write_conf "   guest only = $guest_only"

    local browseable_var="SHARE_${i}_BROWSEABLE"
    local browseable
    browseable=$(normalize_bool "${!browseable_var:-yes}" "yes")
    write_conf "   browseable = $browseable"

    local read_only_var="SHARE_${i}_READ_ONLY"
    local writeable_var="SHARE_${i}_WRITEABLE"
    local read_only writeable
    read_only=$(normalize_bool "${!read_only_var:-yes}" "yes")
    writeable=$(normalize_bool "${!writeable_var:-no}" "no")

    if [[ "$read_only" == "no" || "$writeable" == "yes" ]]; then
        writeable="yes"
    else
        writeable="no"
    fi
    write_conf "   writable = $writeable"

    local read_list_var="SHARE_${i}_READ_LIST"
    local write_list_var="SHARE_${i}_WRITE_LIST"
    [[ -n "${!read_list_var:-}" ]] && write_conf "   read list = ${!read_list_var}"
    [[ -n "${!write_list_var:-}" ]] && write_conf "   write list = ${!write_list_var}"

    local create_mask_var="SHARE_${i}_CREATE_MASK"
    local force_create_mask_var="SHARE_${i}_FORCE_CREATE_MASK"
    local dir_mask_var="SHARE_${i}_DIRECTORY_MASK"
    local force_dir_mask_var="SHARE_${i}_FORCE_DIRECTORY_MASK"

    validate_numeric "${!create_mask_var:-}" && write_conf "   create mask = ${!create_mask_var}"
    validate_numeric "${!force_create_mask_var:-}" && write_conf "   force create mask = ${!force_create_mask_var}"
    validate_numeric "${!dir_mask_var:-}" && write_conf "   directory mask = ${!dir_mask_var}"
    validate_numeric "${!force_dir_mask_var:-}" && write_conf "   force directory mask = ${!force_dir_mask_var}"

    local force_user_var="SHARE_${i}_FORCE_USER"
    local force_group_var="SHARE_${i}_FORCE_GROUP"
    [[ -n "${!force_user_var:-}" ]] && write_conf "   force user = ${!force_user_var}"
    [[ -n "${!force_group_var:-}" ]] && write_conf "   force group = ${!force_group_var}"

    local recycle_var="SHARE_${i}_RECYCLE_BIN"
    local btrfs_var="SHARE_${i}_IS_BTRFS"
    local recycle btrfs vfs_modules
    
    recycle=$(normalize_bool "${!recycle_var:-no}" "no")
    btrfs=$(normalize_bool "${!btrfs_var:-no}" "no")
    
    vfs_modules="${BASE_VFS_MODULES:-}"
    [[ "$recycle" == "yes" ]] && vfs_modules="$vfs_modules recycle"
    [[ "$btrfs" == "yes" ]] && vfs_modules="$vfs_modules btrfs"
    
    write_conf "   vfs objects = $vfs_modules"

    if [[ "$recycle" == "yes" ]]; then
        local recycle_max_var="SHARE_${i}_RECYCLE_MAX_SIZE"
        local recycle_dir_mode_var="SHARE_${i}_RECYCLE_DIRECTORY_MODE"
        local recycle_subdir_mode_var="SHARE_${i}_RECYCLE_SUB_DIRECTORY_MODE"

        write_conf "   recycle:repository = $DATA_DIR/$share_name/.recycle/%U"
        write_conf "   recycle:keeptree = yes"
        write_conf "   recycle:versions = yes"
        write_conf "   recycle:touch = yes"
        write_conf "   recycle:touch_mtime = no"
        
        if validate_numeric "${!recycle_dir_mode_var:-}"; then
            write_conf "   recycle:directory_mode = ${!recycle_dir_mode_var}"
        else
            write_conf "   recycle:directory_mode = 0777"
        fi
        
        if validate_numeric "${!recycle_subdir_mode_var:-}"; then
            write_conf "   recycle:subdir_mode = ${!recycle_subdir_mode_var}"
        else
            write_conf "   recycle:subdir_mode = 0700"
        fi
        
        validate_numeric "${!recycle_max_var:-}" && write_conf "   recycle:maxsize = ${!recycle_max_var}"
        
        write_conf "   recycle:exclude = "
        write_conf "   recycle:exclude_dir = .recycle"
    fi
}

configure_temp_share() {
    local temp_on
    temp_on=$(normalize_bool "${TEMP_SHARE_ON:-no}" "no")
    
    [[ "$temp_on" != "yes" ]] && return

    local temp_name="${TEMP_SHARE_NAME:-temp-share}"

    write_conf ""
    write_conf "#============================ CONFIGURATION FOR: TEMP SHARE (GROUND FOR PUBLIC DATA EXCHANGE) ============================"
    write_conf "[$temp_name]"
    write_conf "   path = $DATA_DIR/$temp_name"
    
    [[ -n "${TEMP_SHARE_COMMENT:-}" ]] && write_conf "   comment = ${TEMP_SHARE_COMMENT}"

    local read_only
    read_only=$(normalize_bool "${TEMP_SHARE_READ_ONLY:-no}" "no")
    write_conf "   read only = $read_only"

    local public
    public=$(normalize_bool "${TEMP_SHARE_PUBLIC:-yes}" "yes")
    write_conf "   public = $public"

    local recycle
    recycle=$(normalize_bool "${TEMP_RECYCLE_BIN:-no}" "no")
    
    local vfs_modules="${BASE_VFS_MODULES:-}"
    [[ "$recycle" == "yes" ]] && vfs_modules="$vfs_modules recycle"
    
    write_conf "   vfs objects = $vfs_modules"

    if [[ "$recycle" == "yes" ]]; then
        write_conf "   recycle:repository = $DATA_DIR/$temp_name/.recycle/%U"
        write_conf "   recycle:keeptree = yes"
        write_conf "   recycle:versions = yes"
        write_conf "   recycle:touch = yes"
        write_conf "   recycle:touch_mtime = no"
        
        if validate_numeric "${TEMP_RECYCLE_DIRECTORY_MODE:-}"; then
            write_conf "   recycle:directory_mode = ${TEMP_RECYCLE_DIRECTORY_MODE}"
        else
            write_conf "   recycle:directory_mode = 0777"
        fi
        
        if validate_numeric "${TEMP_RECYCLE_SUB_DIRECTORY_MODE:-}"; then
            write_conf "   recycle:subdir_mode = ${TEMP_RECYCLE_SUB_DIRECTORY_MODE}"
        else
            write_conf "   recycle:subdir_mode = 0700"
        fi
        
        validate_numeric "${TEMP_RECYCLE_MAX_SIZE:-}" && write_conf "   recycle:maxsize = ${TEMP_RECYCLE_MAX_SIZE}"
        
        write_conf "   recycle:exclude = "
        write_conf "   recycle:exclude_dir = .recycle"
    fi

    write_conf ""
    write_conf "#============================ CONFIGURATION FOR TEMP SHARE ENDS HERE ============================"
}

main() {
    create_share_directories
    global_config

    write_conf ""
    write_conf "#============================ CONFIGURATION FOR NAS STARTS HERE ============================"
    write_conf ""
    write_conf "#============================ SHARE DEFINITIONS =============================="

    local share_indices
    share_indices=$(get_share_indices)
    
    if [[ -n "$share_indices" ]]; then
        while IFS= read -r i; do
            configure_share "$i" || continue
        done <<< "$share_indices"
    fi

    write_conf ""
    write_conf "#============================ CONFIGURATION FOR USER SHARES ENDS HERE ============================"

    configure_temp_share

    write_conf "#============================ CONFIGURATION FOR NAS ENDS HERE ============================"
}

main