#!/bin/bash
# constructConf.sh - Comprehensive Samba configuration with all critical parameters
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

# Script metadata (conditional to avoid conflicts when sourced)
if [[ -z "${CONSTRUCT_CONF_SCRIPT_NAME:-}" ]]; then
    CONSTRUCT_CONF_SCRIPT_NAME="$(basename "$0")"
    readonly CONSTRUCT_CONF_SCRIPT_NAME
fi
if [[ -z "${CONSTRUCT_CONF_SCRIPT_VERSION:-}" ]]; then
    # CONSTRUCT_CONF_SCRIPT_VERSION format YYYY.MM.DD
    readonly CONSTRUCT_CONF_SCRIPT_VERSION="2025.11.24"
fi

LOG_FILE="${LOG_FILE:-/var/log/nas-setup.log}"
PROFILE_MODE="${PROFILE_MODE:-0}"

readonly SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"
readonly GUEST_ACC="/etc/samba/guest.acc"
readonly DATA_DIR="${DATA_DIR:-/data}"

# Samba directory paths - with secure defaults
readonly LOCK_DIR="${SAMBA_LOCK_DIR:-/var/lib/samba/locks}"
readonly PID_DIR="${SAMBA_PID_DIR:-/var/run/samba}"
readonly PRIVATE_DIR="${SAMBA_PRIVATE_DIR:-/var/lib/samba/private}"
readonly STATE_DIR="${SAMBA_STATE_DIR:-/var/lib/samba}"
readonly CACHE_DIR="${SAMBA_CACHE_DIR:-/var/cache/samba}"

declare -A GROUP_CACHE=()
declare -A PASSWD_CACHE=()
declare -i PERF_START_TIME=0

# === Numeric validation for IDs only ===
validate_numeric() {
    local value="$1"
    
    [[ -z "$value" ]] && return 1
    value="${value##+(0)}"
    [[ -z "$value" ]] && value="0"
    
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
        return 0
    fi
    return 1
}

# === Safe arithmetic wrapper ===
safe_arithmetic() {
    local var1="${1}"
    local op="${2}"
    local var2="${3}"
    
    var1=$(validate_numeric "$var1" 2>/dev/null) || var1="0"
    var2=$(validate_numeric "$var2" 2>/dev/null) || var2="0"
    
    local result
    case "$op" in
        +) result=$((var1 + var2)) ;;
        -) result=$((var1 - var2)) ;;
        \*) result=$((var1 * var2)) ;;
        /) result=$((var1 / var2)) ;;
        %) result=$((var1 % var2)) ;;
        *) return 1 ;;
    esac
    echo "$result"
}

# ============================================================================
# COLOR PALETTE - Elegant Terminal Output (Conditional - avoid conflicts)
# ============================================================================

# === Status Colors ===
if [[ -z "${SUCCESS_GREEN:-}" ]]; then
    readonly SUCCESS_GREEN='\033[38;5;10m'
    readonly ERROR_RED='\033[38;5;9m'
    readonly WARNING_YELLOW='\033[38;5;11m'
    readonly INFO_CYAN='\033[38;5;14m'
fi

# === Accent Colors ===
if [[ -z "${ORANGE:-}" ]]; then
    readonly ORANGE='\033[38;5;208m'
    readonly LITE_GREEN='\033[38;5;10m'
    readonly NAVY_BLUE='\033[38;5;18m'
    readonly GREEN='\033[38;5;2m'
    readonly SEA_GREEN='\033[38;5;74m'
    readonly BLUE='\033[38;5;12m'
    readonly ASH_GRAY='\033[38;5;250m'
fi

# === Special Colors ===
if [[ -z "${TEAL:-}" ]]; then
    readonly TEAL='\033[38;5;45m'
    readonly PINK='\033[38;5;213m'
    readonly WHITE='\033[38;5;15m'
    readonly DARK_GRAY='\033[38;5;240m'
    readonly LIGHT_GRAY='\033[38;5;252m'
fi

# === Reset ===
if [[ -z "${NC:-}" ]]; then
    readonly NC='\033[0m'
    readonly BOLD='\033[1m'
fi

# === Logging Functions ===
log_info() {
    printf "${INFO_CYAN}[%s] [i INFO]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

log_error() {
    printf "${ERROR_RED}[%s] [✗ ERROR]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2 | tee -a "$LOG_FILE"
}

log_warn() {
    printf "${WARNING_YELLOW}[%s] [! WARN]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2 | tee -a "$LOG_FILE"
}

progress() {
    printf "${SEA_GREEN}[%s] [> PROGRESS]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

log_success() {
    printf "${SUCCESS_GREEN}[%s] [✓ SUCCESS]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

exit_error() {
    log_error "$*"
    exit 1
}

# === Utility Functions ===
print_header() {
    printf "\n${BOLD}${NAVY_BLUE}═══════════════════════════════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"
    printf "${BOLD}${NAVY_BLUE}   %s${NC}\n" "$*" | tee -a "$LOG_FILE"
    printf "${BOLD}${NAVY_BLUE}═══════════════════════════════════════════════════════════════════${NC}\n\n" | tee -a "$LOG_FILE"
}

print_check() {
    printf "  ${SUCCESS_GREEN}✓${NC} %s\n" "$*" | tee -a "$LOG_FILE"
}

cleanup() {
    [[ $? -eq 0 ]] || log_error "Script terminated unexpectedly"
}
trap cleanup EXIT

perf_start() {
    PERF_START_TIME=$(date +%s%N 2>/dev/null || date +%s)
}

perf_mark() {
    local name="$1"
    local current_time
    current_time=$(date +%s%N 2>/dev/null || date +%s)
    
    local elapsed
    elapsed=$(safe_arithmetic "$current_time" "-" "$PERF_START_TIME" 2>/dev/null) || elapsed=0
    
    if [[ $elapsed -gt 1000000 ]]; then
        elapsed=$((elapsed / 1000000))
    else
        elapsed=0
    fi
    
    [[ "$PROFILE_MODE" == "1" ]] && progress "[PROFILE] $name: ${elapsed}ms"
}

normalize_bool() {
    local val="${1,,}"
    case "$val" in
        yes|y|ye|true|t|1) echo "yes" ;;
        no|n|false|f|0) echo "no" ;;
        *) echo "${2:-no}" ;;
    esac
}

load_group_cache() {
    progress "Loading system group database..."
    while IFS=: read -r group _ gid members; do
        GROUP_CACHE[$group]="$gid|$members"
    done < <(getent group)
    log_info "Cached ${#GROUP_CACHE[@]} groups"
}

load_passwd_cache() {
    progress "Loading system password database..."
    while IFS=: read -r user _ uid _ _ _ _; do
        PASSWD_CACHE[$user]=$uid
    done < <(getent passwd)
    log_info "Cached ${#PASSWD_CACHE[@]} users"
}

gid_exists() {
    [[ -n "${GROUP_CACHE[$1]:-}" ]]
}

uid_exists() {
    [[ -n "${PASSWD_CACHE[$1]:-}" ]]
}

write_conf() {
    printf '%s\n' "$1" >> "$SMB_CONF"
}

get_share_indices() {
    compgen -v SHARE_NAME_ 2>/dev/null | sed 's/SHARE_NAME_//' | sort -n || true
}

validate_group_references() {
    log_info "Validating group and user references in share configuration..."
    
    # Check if validation should be skipped
    local skip_validation="${SKIP_USER_VALIDATION:-no}"
    skip_validation=$(normalize_bool "$skip_validation" "no")
    
    if [[ "$skip_validation" == "yes" ]]; then
        log_warn "User/group validation SKIPPED - ensure users are created before Samba starts"
        return 0
    fi
    
    progress "Loading system databases for validation..."
    
    load_group_cache
    load_passwd_cache
    
    local share_indices
    share_indices=$(get_share_indices)
    
    [[ -z "$share_indices" ]] && { log_info "No shares to validate"; return 0; }
    
    local validation_count=0
    
    while IFS= read -r i; do
        local share_name_var="SHARE_NAME_$i"
        local share_name="${!share_name_var:-}"
        
        [[ -z "$share_name" ]] && continue
        
        for ref_var in VALID_USERS READ_LIST WRITE_LIST; do
            local full_var="SHARE_${i}_${ref_var}"
            local value="${!full_var:-}"
            
            [[ -z "$value" ]] && continue
            
            # Use eval to properly split the value by spaces
            eval "local -a tokens=($value)"
            
            local token
            for token in "${tokens[@]}"; do
                [[ -z "$token" ]] && continue
                
                if [[ "$token" == @* ]]; then
                    local group="${token#@}"
                    if ! gid_exists "$group"; then
                        log_warn "Referenced group '@$group' does not exist - will be created or skipped at runtime"
                    else
                        progress "✓ Validated group reference: @$group"
                        ((validation_count++))
                    fi
                else
                    if ! uid_exists "$token"; then
                        log_warn "Referenced user '$token' does not exist - will be created or skipped at runtime"
                    else
                        progress "✓ Validated user reference: $token"
                        ((validation_count++))
                    fi
                fi
            done
        done
    done <<< "$share_indices"
    
    log_info "User/group validation complete ($validation_count valid references found)"
}

# === FEATURE 1 & 8: Directory Ownership & Shared Group Permissions ===
setup_share_permissions() {
    local share_path="$1"
    local owner="$2"
    local group="${3:-$owner}"
    local permission_mode="${4:-2770}"
    local recursive="${5:-no}"
    
    # Verify owner exists
    if ! id "$owner" >/dev/null 2>&1; then
        log_warn "Owner '$owner' does not exist, skipping permission setup for $share_path"
        return 0
    fi
    
    # Verify group exists
    if ! getent group "$group" >/dev/null 2>&1; then
        log_warn "Group '$group' does not exist, skipping group assignment for $share_path"
        return 0
    fi
    
    # Set ownership (with optional recursion)
    local chown_flags=""
    [[ "$recursive" == "yes" ]] && chown_flags="-R"
    
    if chown $chown_flags "$owner:$group" "$share_path" 2>/dev/null; then
        if [[ "$recursive" == "yes" ]]; then
            log_info "✓ Set ownership (recursively): $owner:$group for $share_path"
        else
            log_info "✓ Set ownership: $owner:$group for $share_path"
        fi
    else
        log_error "Failed to set ownership for $share_path"
        return 1
    fi
    
    # Set permissions (with optional recursion)
    local chmod_flags=""
    [[ "$recursive" == "yes" ]] && chmod_flags="-R"
    
    if chmod $chmod_flags "$permission_mode" "$share_path" 2>/dev/null; then
        if [[ "$recursive" == "yes" ]]; then
            log_info "✓ Set permissions (recursively): $permission_mode for $share_path"
        else
            log_info "✓ Set permissions: $permission_mode for $share_path"
        fi
        
        # Check if SGID bit is set
        if [[ "$permission_mode" =~ ^2 ]]; then
            log_info "  > SGID bit enabled: new files will inherit group '$group'"
        fi
        
        # If recursive and SGID, ensure all subdirectories have SGID too
        if [[ "$recursive" == "yes" && "$permission_mode" =~ ^2 ]]; then
            find "$share_path" -type d -exec chmod g+s {} \; 2>/dev/null
            log_info "  > Applied SGID to all subdirectories"
        fi
    else
        log_error "Failed to set permissions for $share_path"
        return 1
    fi
    
    return 0
}

create_share_directories() {
    log_info "Creating share directories..."
    
    local share_indices
    share_indices=$(get_share_indices)
    
    [[ -z "$share_indices" ]] && return 0
    
    local dir_count=0
    
    # Global recursive ownership setting (can be overridden per-share)
    local global_recursive
    global_recursive=$(normalize_bool "${SHARE_RECURSIVE_OWNERSHIP:-no}" "no")
    
    while IFS= read -r i; do
        local share_name_var="SHARE_NAME_$i"
        local share_name="${!share_name_var:-}"
        
        [[ -z "$share_name" ]] && continue
        
        local share_path="$DATA_DIR/$share_name"
        if [[ ! -e "$share_path" ]]; then
            mkdir -p "$share_path"
            progress "Created share directory: $share_path"
            ((dir_count++))
        fi
        
        # Setup ownership and permissions
        local owner_var="SHARE_${i}_OWNER"
        local group_var="SHARE_${i}_OWNER_GROUP"
        local perms_var="SHARE_${i}_PERMISSION_MODE"
        local recursive_var="SHARE_${i}_RECURSIVE_OWNERSHIP"
        
        local owner="${!owner_var:-}"
        local group="${!group_var:-}"
        local perms="${!perms_var:-}"
        local recursive="${!recursive_var:-}"
        
        # If owner is specified, setup permissions
        if [[ -n "$owner" ]]; then
            # Default group to owner if not specified
            [[ -z "$group" ]] && group="$owner"
            # Default permission mode if not specified
            [[ -z "$perms" ]] && perms="2770"
            # Use per-share recursive setting, or fall back to global
            [[ -z "$recursive" ]] && recursive="$global_recursive"
            
            # Normalize recursive setting
            recursive=$(normalize_bool "$recursive" "no")
            
            setup_share_permissions "$share_path" "$owner" "$group" "$perms" "$recursive"
        fi
        
        local recycle_var="SHARE_${i}_RECYCLE_BIN"
        local recycle
        recycle=$(normalize_bool "${!recycle_var:-no}" "no")
        
        if [[ "$recycle" == "yes" ]]; then
            local recycle_path="$share_path/.recycle"
            if [[ ! -e "$recycle_path" ]]; then
                mkdir -p "$recycle_path"
                progress "Created recycle bin: $recycle_path"
                ((dir_count++))
            fi
        fi
    done <<< "$share_indices"
    
    log_info "Directory creation complete ($dir_count directories created)"
}

global_config() {
    log_info "Generating global Samba configuration..."
    
    cat > "$SMB_CONF" << 'EOF'
[global]
EOF

    # === Naming & Identity Settings ===
    local netbios_name="${NETBIOS_NAME:-NASSERVER}"
    netbios_name="${netbios_name:0:15}"  # Max 15 chars
    write_conf "   netbios name = $netbios_name"
    
    write_conf "   workgroup = ${SMB_WORKGROUP:-WORKGROUP}"
    write_conf "   server string = ${SERVER_STRING:-Samba NAS Server}"

    # === Security Settings ===
    local security_mode="${SECURITY_MODE:-user}"
    security_mode="${security_mode,,}"
    case "$security_mode" in
        user|share|ads|domain) write_conf "   security = $security_mode" ;;
        *) write_conf "   security = user" ;;
    esac

    local passdb_backend="${PASSDB_BACKEND:-tdbsam}"
    write_conf "   passdb backend = $passdb_backend"

    write_conf "   server role = ${SERVER_ROLE:-standalone server}"

    # === Logging Settings ===
    # === Basic Configuration Info ===
    local max_open_files="${MAX_OPEN_FILES:-30000}"
    max_open_files=$(validate_numeric "$max_open_files" 2>/dev/null) || max_open_files=30000
    write_conf "   max open files = $max_open_files"

    # === Protocol & Encryption Settings ===
    # Research: SMB3_11 is minimum for modern security (Windows 10/11, Server 2016+)
    # Never set server_max_protocol - let Samba default to latest stable version
    local server_min_protocol="${SERVER_MIN_PROTOCOL:-SMB3_11}"
    write_conf "   server min protocol = $server_min_protocol"
    
    local server_max_protocol="${SERVER_MAX_PROTOCOL:-}"
    if [[ -n "$server_max_protocol" ]]; then
        write_conf "   server max protocol = $server_max_protocol"
    fi
    
    local client_min_protocol="${CLIENT_MIN_PROTOCOL:-SMB3_11}"
    write_conf "   client min protocol = $client_min_protocol"
    
    local client_max_protocol="${CLIENT_MAX_PROTOCOL:-}"
    if [[ -n "$client_max_protocol" ]]; then
        write_conf "   client max protocol = $client_max_protocol"
    fi

    # === Encryption Settings ===
    # Research: "desired" is optimal balance (auto-negotiates, doesn't block SMB3 clients)
    # Microsoft/Samba best practice: don't force encryption unless required by policy
    local encrypt="${GLOBAL_ENCRYPT:-desired}"
    encrypt="${encrypt,,}"
    case "$encrypt" in
        required|enable|enabled|mandatory) encrypt="required" ;;
        desired|auto|default) encrypt="desired" ;;
        disable|disabled|off|no) encrypt="disabled" ;;
        *) encrypt="desired" ;;
    esac
    GLOBAL_ENCRYPT="$encrypt"
    write_conf "   smb encrypt = $encrypt"
    write_conf "   server smb encrypt = $encrypt"
    write_conf "   client smb encrypt = ${CLIENT_SMB_ENCRYPT:-$encrypt}"

    # SMB3 Encryption Algorithms (SMB 3.1.1+)
    # Research: AES-128-GCM fastest with CPU AES acceleration, AES-256-GCM strongest
    # Windows Server 2022/Windows 11 added AES-256, but AES-128-GCM is default for speed
    local smb3_encrypt="${SMB3_ENCRYPTION_ALGORITHMS:-AES-128-GCM, AES-128-CCM}"
    write_conf "   server smb3 encryption algorithms = $smb3_encrypt"
    write_conf "   client smb3 encryption algorithms = ${CLIENT_SMB3_ENCRYPTION_ALGORITHMS:-$smb3_encrypt}"

    # === Signing Settings ===
    # Research: mandatory signing is Windows Server 2022+ default for security
    # Minimal performance impact on modern CPUs with AES-NI
    local server_signing="${SERVER_SIGNING:-mandatory}"
    server_signing="${server_signing,,}"
    case "$server_signing" in
        mandatory|required) server_signing="mandatory" ;;
        auto|default) server_signing="auto" ;;
        disabled|off|no) server_signing="disabled" ;;
        *) server_signing="mandatory" ;;
    esac
    write_conf "   server signing = $server_signing"
    
    local client_signing="${CLIENT_SIGNING:-mandatory}"
    client_signing="${client_signing,,}"
    case "$client_signing" in
        mandatory|required) client_signing="mandatory" ;;
        auto|default) client_signing="auto" ;;
        disabled|off|no) client_signing="disabled" ;;
        *) client_signing="mandatory" ;;
    esac
    write_conf "   client signing = $client_signing"
    
    local client_ipc_signing="${CLIENT_IPC_SIGNING:-required}"
    client_ipc_signing="${client_ipc_signing,,}"
    case "$client_ipc_signing" in
        required|mandatory) client_ipc_signing="required" ;;
        auto|default) client_ipc_signing="auto" ;;
        disabled|off|no) client_ipc_signing="disabled" ;;
        *) client_ipc_signing="required" ;;
    esac
    write_conf "   client ipc signing = $client_ipc_signing"

    # SMB3 Signing Algorithms (SMB 3.1.1+)
    # Research: AES-128-GMAC fastest, introduced in Windows Server 2022
    local smb3_signing="${SMB3_SIGNING_ALGORITHMS:-AES-128-GMAC, AES-128-CMAC}"
    write_conf "   server smb3 signing algorithms = $smb3_signing"
    write_conf "   client smb3 signing algorithms = ${CLIENT_SMB3_SIGNING_ALGORITHMS:-$smb3_signing}"

    # === Authentication Security ===
    # Research: NTLMv2-only is safe, disabled only for high-security environments with Kerberos
    local ntlm_auth="${NTLM_AUTH:-ntlmv2-only}"
    ntlm_auth="${ntlm_auth,,}"
    case "$ntlm_auth" in
        disabled|no|off) ntlm_auth="disabled" ;;
        ntlmv2-only|ntlmv2only|ntlmv2) ntlm_auth="ntlmv2-only" ;;
        ntlmv1-permitted|yes) ntlm_auth="ntlmv1-permitted" ;;
        *) ntlm_auth="ntlmv2-only" ;;
    esac
    write_conf "   ntlm auth = $ntlm_auth"
    
    local lanman_auth=$(normalize_bool "${LANMAN_AUTH:-no}" "no")
    write_conf "   lanman auth = $lanman_auth"
    
    local client_ntlmv2_auth=$(normalize_bool "${CLIENT_NTLMV2_AUTH:-yes}" "yes")
    write_conf "   client ntlmv2 auth = $client_ntlmv2_auth"
    
    local client_lanman_auth=$(normalize_bool "${CLIENT_LANMAN_AUTH:-no}" "no")
    write_conf "   client lanman auth = $client_lanman_auth"
    
    local client_plaintext_auth=$(normalize_bool "${CLIENT_PLAINTEXT_AUTH:-no}" "no")
    write_conf "   client plaintext auth = $client_plaintext_auth"
    
    # Research: restrict_anonymous = 2 is most secure (require authentication)
    local restrict_anonymous="${RESTRICT_ANONYMOUS:-2}"
    restrict_anonymous=$(validate_numeric "$restrict_anonymous" 2>/dev/null) || restrict_anonymous=2
    if [[ "$restrict_anonymous" -ge 0 && "$restrict_anonymous" -le 2 ]]; then
        write_conf "   restrict anonymous = $restrict_anonymous"
    fi
    
    local null_passwords=$(normalize_bool "${NULL_PASSWORDS:-no}" "no")
    write_conf "   null passwords = $null_passwords"

    # === Networking Settings ===
    local interfaces="${SAMBA_INTERFACES:-}"
    local bind_interfaces_only="${BIND_INTERFACES_ONLY:-no}"
    bind_interfaces_only=$(normalize_bool "$bind_interfaces_only" "no")

    if [[ -n "$interfaces" ]]; then
        write_conf "   interfaces = $interfaces"
    fi
    write_conf "   bind interfaces only = $bind_interfaces_only"

    local disable_netbios netbios_port smb_port
    # Research (Nov 2025): Windows Server 2025 no longer opens NetBIOS ports by default
    # NetBIOS was only necessary for SMB1 usage, which is deprecated
    disable_netbios=$(normalize_bool "${DISABLE_NETBIOS:-yes}" "yes")
    
    netbios_port=$(validate_numeric "${NETBIOS_PORT:-139}" 2>/dev/null) || netbios_port=139
    smb_port=$(validate_numeric "${SMB_PORT:-445}" 2>/dev/null) || smb_port=445
    
    write_conf "   disable netbios = $disable_netbios"
    if [[ "$disable_netbios" == "yes" ]]; then
        write_conf "   smb ports = $smb_port"
    else
        write_conf "   smb ports = $smb_port $netbios_port"
    fi
    
    # === Network Services ===
    local wins_support=$(normalize_bool "${WINS_SUPPORT:-no}" "no")
    write_conf "   wins support = $wins_support"
    
    local local_master=$(normalize_bool "${LOCAL_MASTER:-no}" "no")
    write_conf "   local master = $local_master"
    
    local preferred_master=$(normalize_bool "${PREFERRED_MASTER:-no}" "no")
    write_conf "   preferred master = $preferred_master"
    
    local domain_master=$(normalize_bool "${DOMAIN_MASTER:-no}" "no")
    write_conf "   domain master = $domain_master"

    # === Logging Settings ===
    # Research: Level 0-1 = production (<1% impact), Level 2 = troubleshooting (2-3%), 
    # Level 3+ = debugging (5-30% impact), never use >3 in production
    local log_level="${LOG_LEVEL:-1}"
    log_level=$(validate_numeric "$log_level" 2>/dev/null) || log_level=1
    if [[ "$log_level" -ge 0 && "$log_level" -le 10 ]]; then
        write_conf "   log level = $log_level"
    fi
    
    # Research: 50MB (50000 KB) is good balance for rotation
    local max_log_size="${MAX_LOG_SIZE:-50000}"
    max_log_size=$(validate_numeric "$max_log_size" 2>/dev/null) || max_log_size=50000
    write_conf "   max log size = $max_log_size"
    
    # Research: %m (client machine name) allows per-client troubleshooting
    local log_file="${LOG_FILE:-/var/log/samba/%m.log}"
    write_conf "   log file = $log_file"
    
    # Research: syslog = 0 is optimal (use file logging for performance)
    local syslog="${SYSLOG:-0}"
    syslog=$(validate_numeric "$syslog" 2>/dev/null) || syslog=0
    write_conf "   syslog = $syslog"
    
    local syslog_only=$(normalize_bool "${SYSLOG_ONLY:-no}" "no")
    write_conf "   syslog only = $syslog_only"
    
    # Research: Always include timestamp, PID, UID for troubleshooting
    local debug_timestamp=$(normalize_bool "${DEBUG_TIMESTAMP:-yes}" "yes")
    write_conf "   debug timestamp = $debug_timestamp"
    
    local debug_pid=$(normalize_bool "${DEBUG_PID:-yes}" "yes")
    write_conf "   debug pid = $debug_pid"
    
    local debug_uid=$(normalize_bool "${DEBUG_UID:-yes}" "yes")
    write_conf "   debug uid = $debug_uid"
    
    local logging="${LOGGING:-file}"
    if [[ "$logging" == "syslog" || "$logging" == "file" ]]; then
        write_conf "   logging = $logging"
    fi

    # === Samba Directory Paths ===
    write_conf "   lock dir = $LOCK_DIR"
    write_conf "   pid directory = $PID_DIR"
    write_conf "   private dir = $PRIVATE_DIR"
    write_conf "   state directory = $STATE_DIR"
    write_conf "   cache directory = $CACHE_DIR"

    # === Name Resolution ===
    local name_resolve_order="${NAME_RESOLVE_ORDER:-bcast host lmhosts wins}"
    write_conf "   name resolve order = $name_resolve_order"

    local dns_proxy="${DNS_PROXY:-no}"
    dns_proxy=$(normalize_bool "$dns_proxy" "no")
    write_conf "   dns proxy = $dns_proxy"

    # === Guest & User Mapping ===
    local map_to_guest="${MAP_TO_GUEST:-Never}"
    map_to_guest="${map_to_guest,,}"
    case "$map_to_guest" in
        "bad user"|baduser) write_conf "   map to guest = Bad User" ;;
        "bad password"|badpassword) write_conf "   map to guest = Bad Password" ;;
        "never"|no) write_conf "   map to guest = Never" ;;
        *) write_conf "   map to guest = Never" ;;
    esac

    if [[ -e "$GUEST_ACC" ]]; then
        write_conf "   guest account = ${GUEST_ACCOUNT:-guest}"
    fi

    # === File Handling & Performance ===
    # Research: sendfile provides 30% speedup with zero-copy transfers
    local use_sendfile=$(normalize_bool "${USE_SENDFILE:-yes}" "yes")
    write_conf "   use sendfile = $use_sendfile"
    
    # Research: 16KB is optimal for most networks (balance between overhead and efficiency)
    # Values over 65KB waste memory, under 2KB cause problems
    local min_receivefile_size="${MIN_RECEIVEFILE_SIZE:-16384}"
    min_receivefile_size=$(validate_numeric "$min_receivefile_size" 2>/dev/null) || min_receivefile_size=16384
    write_conf "   min receivefile size = $min_receivefile_size"
    
    # Research: 16KB threshold for async I/O gives 15-30% speedup on large files
    # Modern SSDs benefit from async I/O, HDDs may want larger (65536)
    local aio_read_size="${AIO_READ_SIZE:-16384}"
    aio_read_size=$(validate_numeric "$aio_read_size" 2>/dev/null) || aio_read_size=16384
    write_conf "   aio read size = $aio_read_size"
    
    local aio_write_size="${AIO_WRITE_SIZE:-16384}"
    aio_write_size=$(validate_numeric "$aio_write_size" 2>/dev/null) || aio_write_size=16384
    write_conf "   aio write size = $aio_write_size"
    
    # Research: read/write raw enabled by default, provides low-latency operations
    local read_raw=$(normalize_bool "${READ_RAW:-yes}" "yes")
    write_conf "   read raw = $read_raw"
    
    local write_raw=$(normalize_bool "${WRITE_RAW:-yes}" "yes")
    write_conf "   write raw = $write_raw"
    
    # Research: 65535 is maximum negotiated packet size (default), optimal for gigabit+
    local max_xmit="${MAX_XMIT:-65535}"
    max_xmit=$(validate_numeric "$max_xmit" 2>/dev/null) || max_xmit=65535
    if [[ "$max_xmit" -ge 1024 && "$max_xmit" -le 65535 ]]; then
        write_conf "   max xmit = $max_xmit"
    fi
    
    # === Connection Management ===
    # Research: 300 seconds (5 min) is standard TCP keepalive for reliable clients
    # Lower to 30-60 for unreliable networks
    local keepalive="${KEEPALIVE:-300}"
    keepalive=$(validate_numeric "$keepalive" 2>/dev/null) || keepalive=300
    write_conf "   keepalive = $keepalive"
    
    # Research: 15 minutes is optimal balance (prevents resource exhaustion without annoying users)
    # Busy servers: 5-10 min, home use: 30-60 min, 0 = never (not recommended)
    local deadtime_conn="${DEADTIME:-15}"
    deadtime_conn=$(validate_numeric "$deadtime_conn" 2>/dev/null) || deadtime_conn=15
    write_conf "   deadtime = $deadtime_conn"

    # === Locking & Oplocks ===
    # Research: strict_locking = no is optimal (only check when requested, not every access)
    # Only set "yes" for databases or corruption-prone applications
    local strict_locking=$(normalize_bool "${STRICT_LOCKING:-no}" "no")
    write_conf "   strict locking = $strict_locking"
    
    # Research: oplocks provide 30% performance improvement through client-side caching
    # Essential for good performance, only disable for databases
    local oplocks=$(normalize_bool "${OPLOCKS:-yes}" "yes")
    write_conf "   oplocks = $oplocks"
    
    # Research: level2 oplocks allow read sharing with caching (good for collaboration)
    local level2_oplocks=$(normalize_bool "${LEVEL2_OPLOCKS:-yes}" "yes")
    write_conf "   level2 oplocks = $level2_oplocks"
    
    # Research: kernel oplocks coordinate with local file access (important for NAS)
    local kernel_oplocks=$(normalize_bool "${KERNEL_OPLOCKS:-yes}" "yes")
    write_conf "   kernel oplocks = $kernel_oplocks"
    
    # Research: getwd_cache caches working directory paths (good for printer servers)
    local getwd_cache=$(normalize_bool "${GETWD_CACHE:-yes}" "yes")
    write_conf "   getwd cache = $getwd_cache"

    # === Host Access Control ===
    if [[ -n "${HOSTS_ALLOW:-}" ]]; then
        write_conf "   hosts allow = $HOSTS_ALLOW"
    fi
    
    if [[ -n "${HOSTS_DENY:-}" ]]; then
        write_conf "   hosts deny = $HOSTS_DENY"
    fi

    # === Unix Permissions & Symlinks ===
    local unix_extensions=$(normalize_bool "${UNIX_EXTENSIONS:-yes}" "yes")
    write_conf "   unix extensions = $unix_extensions"
    
    local wide_links=$(normalize_bool "${WIDE_LINKS:-no}" "no")
    write_conf "   wide links = $wide_links"
    
    local follow_symlinks=$(normalize_bool "${FOLLOW_SYMLINKS:-yes}" "yes")
    write_conf "   follow symlinks = $follow_symlinks"
    
    local create_mask="${CREATE_MASK:-0664}"
    write_conf "   create mask = $create_mask"
    
    local directory_mask="${DIRECTORY_MASK:-0775}"
    write_conf "   directory mask = $directory_mask"
    
    write_conf "   dont descend = /proc,/dev,/etc,/lib,/lost+found,/initrd"
    
    # === File Attributes ===
    local store_dos_attributes=$(normalize_bool "${STORE_DOS_ATTRIBUTES:-yes}" "yes")
    write_conf "   store dos attributes = $store_dos_attributes"
    
    local map_archive=$(normalize_bool "${MAP_ARCHIVE:-no}" "no")
    write_conf "   map archive = $map_archive"
    
    local map_system=$(normalize_bool "${MAP_SYSTEM:-no}" "no")
    write_conf "   map system = $map_system"
    
    local map_hidden=$(normalize_bool "${MAP_HIDDEN:-no}" "no")
    write_conf "   map hidden = $map_hidden"

    # === Character Encoding ===
    local unix_charset="${UNIX_CHARSET:-UTF-8}"
    write_conf "   unix charset = $unix_charset"
    
    local dos_charset="${DOS_CHARSET:-CP850}"
    write_conf "   dos charset = $dos_charset"
    
    # === Name Mangling ===
    local mangled_names=$(normalize_bool "${MANGLED_NAMES:-no}" "no")
    write_conf "   mangled names = $mangled_names"

    # === Printing (Disabled by default for NAS) ===
    local load_printers=$(normalize_bool "${LOAD_PRINTERS:-no}" "no")
    write_conf "   load printers = $load_printers"
    
    local printing="${PRINTING:-bsd}"
    write_conf "   printing = $printing"
    
    local printcap_name="${PRINTCAP_NAME:-/dev/null}"
    write_conf "   printcap name = $printcap_name"
    
    local disable_spoolss=$(normalize_bool "${DISABLE_SPOOLSS:-yes}" "yes")
    write_conf "   disable spoolss = $disable_spoolss"

    # === Socket Options ===
    # NOTE: Modern Linux kernels (2.6+) have excellent auto-tuning.
    # Setting socket options manually can DECREASE performance!
    # Only set if you have a specific need (legacy systems, testing, etc.)
    if [[ -n "${SOCKET_OPTIONS:-}" ]]; then
        write_conf "   socket options = $SOCKET_OPTIONS"
    else
        write_conf ";   # socket options - NOT SET (kernel auto-tuning is better!)"
    fi

    # === macOS Support ===
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

    # === NT Pipe Support ===
    local nt_pipe_support="${NT_PIPE_SUPPORT:-yes}"
    nt_pipe_support=$(normalize_bool "$nt_pipe_support" "yes")
    write_conf "   nt pipe support = $nt_pipe_support"

    # === Panic Action (Error handling) ===
    local panic_action="${PANIC_ACTION:-/usr/lib/samba/panic-action %d}"
    write_conf "   panic action = $panic_action"
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
    local create_mask force_create_mask dir_mask force_dir_mask
    
    create_mask=$(validate_numeric "${!create_mask_var:-}" 2>/dev/null) && write_conf "   create mask = $create_mask"
    force_create_mask=$(validate_numeric "${!force_create_mask_var:-}" 2>/dev/null) && write_conf "   force create mode = $force_create_mask"
    dir_mask=$(validate_numeric "${!dir_mask_var:-}" 2>/dev/null) && write_conf "   directory mask = $dir_mask"
    force_dir_mask=$(validate_numeric "${!force_dir_mask_var:-}" 2>/dev/null) && write_conf "   force directory mode = $force_dir_mask"

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
        local recycle_dir_mode recycle_subdir_mode recycle_max_size

        write_conf "   recycle:repository = $DATA_DIR/$share_name/.recycle/%U"
        write_conf "   recycle:keeptree = yes"
        write_conf "   recycle:versions = yes"
        write_conf "   recycle:touch = yes"
        write_conf "   recycle:touch_mtime = no"
        
        recycle_dir_mode=$(validate_numeric "${!recycle_dir_mode_var:-}" 2>/dev/null) && write_conf "   recycle:directory_mode = $recycle_dir_mode" || write_conf "   recycle:directory_mode = 0777"
        recycle_subdir_mode=$(validate_numeric "${!recycle_subdir_mode_var:-}" 2>/dev/null) && write_conf "   recycle:subdir_mode = $recycle_subdir_mode" || write_conf "   recycle:subdir_mode = 0700"
        recycle_max_size=$(validate_numeric "${!recycle_max_var:-}" 2>/dev/null) && write_conf "   recycle:maxsize = $recycle_max_size"
        
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
    write_conf "#============================ CONFIGURATION FOR: TEMP SHARE ============================"
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
        local recycle_dir_mode recycle_subdir_mode recycle_max_size
        
        write_conf "   recycle:repository = $DATA_DIR/$temp_name/.recycle/%U"
        write_conf "   recycle:keeptree = yes"
        write_conf "   recycle:versions = yes"
        write_conf "   recycle:touch = yes"
        write_conf "   recycle:touch_mtime = no"
        
        recycle_dir_mode=$(validate_numeric "${TEMP_RECYCLE_DIRECTORY_MODE:-}" 2>/dev/null) && write_conf "   recycle:directory_mode = $recycle_dir_mode" || write_conf "   recycle:directory_mode = 0777"
        recycle_subdir_mode=$(validate_numeric "${TEMP_RECYCLE_SUB_DIRECTORY_MODE:-}" 2>/dev/null) && write_conf "   recycle:subdir_mode = $recycle_subdir_mode" || write_conf "   recycle:subdir_mode = 0700"
        recycle_max_size=$(validate_numeric "${TEMP_RECYCLE_MAX_SIZE:-}" 2>/dev/null) && write_conf "   recycle:maxsize = $recycle_max_size"
        
        write_conf "   recycle:exclude = "
        write_conf "   recycle:exclude_dir = .recycle"
    fi

    write_conf ""
    write_conf "#============================ TEMP SHARE ENDS HERE ============================"
}

validate_samba_config() {
    log_info "Validating Samba configuration with testparm..."
    progress "Running Samba syntax validation..."
    
    if ! command -v testparm &> /dev/null; then
        exit_error "testparm not found. Cannot validate Samba configuration."
    fi
    
    if testparm -s "$SMB_CONF" >/dev/null 2>&1; then
        log_info "✓ Samba configuration validation PASSED"
        return 0
    else
        log_error "Samba configuration validation FAILED"
        exit_error "Configuration is invalid. Run 'testparm $SMB_CONF' for details."
    fi
}

main() {
    {
        perf_start
        
        log_info "=== Samba Configuration Setup Started ==="
        log_info "Script: $CONSTRUCT_CONF_SCRIPT_NAME v$CONSTRUCT_CONF_SCRIPT_VERSION"
        log_info "Timestamp: $(date)"
        log_info "Config file: $SMB_CONF"
        [[ "$PROFILE_MODE" == "1" ]] && log_info "[PROFILE MODE] Enabled"
        
        create_share_directories
        perf_mark "create_share_directories"
        
        validate_group_references
        perf_mark "validate_group_references"
        
        global_config
        perf_mark "global_config"

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
        perf_mark "configure_shares"

        write_conf "#============================ CONFIGURATION FOR NAS ENDS HERE ============================"
        
        validate_samba_config
        perf_mark "validate_samba_config"
        
        log_info "=== Samba Configuration Setup Complete ==="
        
        if [[ "$PROFILE_MODE" == "1" ]]; then
            local total_time
            total_time=$(safe_arithmetic "$(date +%s%N 2>/dev/null || date +%s)" "-" "$PERF_START_TIME" 2>/dev/null) || total_time=0
            if [[ $total_time -gt 1000000 ]]; then
                total_time=$((total_time / 1000000))
            else
                total_time=0
            fi
            log_info "[PROFILE] Total execution time: ${total_time}ms"
        fi
    } 2>&1 | tee -a "$LOG_FILE"
}

main "$@"