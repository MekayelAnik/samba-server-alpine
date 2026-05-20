#!/bin/bash
# constructConf.sh - Samba Configuration Generator (v3.5.5)
# Optimized for multi-client access (Android/Windows/macOS/Linux)
# 
# CRITICAL MULTI-CLIENT NOTES:
# - Oplocks DISABLED by default - prevents file locking issues
# - SMB2 leases DISABLED by default - prevents client-side caching locks
# - Kernel share modes DISABLED - prevents browsing from locking files
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURATION (conditional to avoid conflicts when sourced)
# ============================================================================
# Use unique variable name to avoid conflicts with parent scripts
_CONF_SCRIPT_VERSION="3.5.5"

# Print version immediately on load
echo "[i] === Samba Configuration v${_CONF_SCRIPT_VERSION} ==="

# Only set if not already defined (allows parent script to override)
[[ -z "${SMB_CONF:-}" ]] && SMB_CONF="/etc/samba/smb.conf"
[[ -z "${GUEST_ACC:-}" ]] && GUEST_ACC="/etc/samba/guest.acc"
[[ -z "${DATA_DIR:-}" ]] && DATA_DIR="/data"
[[ -z "${LOG_FILE:-}" ]] && LOG_FILE="/var/log/nas-setup.log"

# Samba directories (with defaults)
[[ -z "${SAMBA_LOCK_DIR:-}" ]] && SAMBA_LOCK_DIR="/var/lib/samba/locks"
[[ -z "${SAMBA_PID_DIR:-}" ]] && SAMBA_PID_DIR="/var/run/samba"
[[ -z "${SAMBA_PRIVATE_DIR:-}" ]] && SAMBA_PRIVATE_DIR="/var/lib/samba/private"
[[ -z "${SAMBA_STATE_DIR:-}" ]] && SAMBA_STATE_DIR="/var/lib/samba"
[[ -z "${SAMBA_CACHE_DIR:-}" ]] && SAMBA_CACHE_DIR="/var/cache/samba"

# Assign to local readonly aliases for use in this script
_SMB_CONF="$SMB_CONF"
_GUEST_ACC="$GUEST_ACC"
_DATA_DIR="$DATA_DIR"
_LOG_FILE="$LOG_FILE"
_LOCK_DIR="$SAMBA_LOCK_DIR"
_PID_DIR="$SAMBA_PID_DIR"
_PRIVATE_DIR="$SAMBA_PRIVATE_DIR"
_STATE_DIR="$SAMBA_STATE_DIR"
_CACHE_DIR="$SAMBA_CACHE_DIR"

# Caches for validation
declare -A GROUP_CACHE=() 2>/dev/null || true
declare -A PASSWD_CACHE=() 2>/dev/null || true

# VFS modules base (set during global config)
BASE_VFS_MODULES=""

# ============================================================================
# COLORS (conditional to avoid conflicts when sourced)
# ============================================================================
if [[ -z "${_CONF_COLORS_SET:-}" ]]; then
    _RED='\033[38;5;9m'
    _GREEN='\033[38;5;10m'
    _YELLOW='\033[38;5;11m'
    _CYAN='\033[38;5;14m'
    _GRAY='\033[38;5;250m'
    _NC='\033[0m'
    _CONF_COLORS_SET=1
fi

# ============================================================================
# LOGGING (use unique function names to avoid conflicts)
# ============================================================================
_conf_log_info()  { printf "${_CYAN:-}[i]${_NC:-} %s\n" "$*" | tee -a "$_LOG_FILE"; }
_conf_log_error() { printf "${_RED:-}[✗]${_NC:-} %s\n" "$*" >&2 | tee -a "$_LOG_FILE"; }
_conf_log_warn()  { printf "${_YELLOW:-}[!]${_NC:-} %s\n" "$*" | tee -a "$_LOG_FILE"; }
_conf_log_ok()    { printf "${_GREEN:-}[✓]${_NC:-} %s\n" "$*" | tee -a "$_LOG_FILE"; }

_conf_error_exit() { _conf_log_error "$*"; exit 1; }

# ============================================================================
# UTILITIES
# ============================================================================
_normalize_bool() {
    case "${1,,}" in
        yes|y|true|t|1) echo "yes" ;;
        no|n|false|f|0) echo "no" ;;
        *) echo "${2:-no}" ;;
    esac
}

_validate_numeric() {
    local val="${1:-}"
    val="${val##+(0)}"
    [[ -z "$val" ]] && val="0"
    [[ "$val" =~ ^[0-9]+$ ]] && echo "$val" && return 0
    return 1
}

_write_conf() {
    printf '%s\n' "$1" >> "$_SMB_CONF"
}

_get_share_indices() {
    compgen -v SHARE_NAME_ 2>/dev/null | sed 's/SHARE_NAME_//' | sort -n || true
}

# ============================================================================
# VALIDATION
# ============================================================================
_load_caches() {
    GROUP_CACHE=()
    PASSWD_CACHE=()
    
    while IFS=: read -r group _ gid members; do
        GROUP_CACHE[$group]="$gid|$members"
    done < <(getent group 2>/dev/null || true)
    
    while IFS=: read -r user _ uid _ _ _ _; do
        PASSWD_CACHE[$user]=$uid
    done < <(getent passwd 2>/dev/null || true)
}

_validate_references() {
    [[ "$(_normalize_bool "${SKIP_USER_VALIDATION:-no}" "no")" == "yes" ]] && return 0
    
    _conf_log_info "Validating user/group references..."
    _load_caches
    
    local indices
    indices=$(_get_share_indices)
    [[ -z "$indices" ]] && return 0
    
    while IFS= read -r i; do
        local share_name_var="SHARE_NAME_$i"
        local share_name="${!share_name_var:-}"
        [[ -z "$share_name" ]] && continue
        
        for ref_var in VALID_USERS READ_LIST WRITE_LIST; do
            local full_var="SHARE_${i}_${ref_var}"
            local value="${!full_var:-}"
            [[ -z "$value" ]] && continue
            
            # Split on spaces (override IFS locally)
            local -a tokens=()
            IFS=' ' read -ra tokens <<< "$value"
            
            for token in "${tokens[@]}"; do
                [[ -z "$token" ]] && continue
                if [[ "$token" == @* ]]; then
                    local group="${token#@}"
                    [[ -z "${GROUP_CACHE[$group]:-}" ]] && \
                        _conf_log_warn "Group '@$group' not found"
                else
                    [[ -z "${PASSWD_CACHE[$token]:-}" ]] && \
                        _conf_log_warn "User '$token' not found"
                fi
            done
        done
    done <<< "$indices"
}

# ============================================================================
# DIRECTORY SETUP
# ============================================================================
_setup_permissions() {
    local path="$1" owner="$2" group="${3:-$2}" mode="${4:-2770}" recursive="${5:-no}"
    
    id "$owner" >/dev/null 2>&1 || return 0
    getent group "$group" >/dev/null 2>&1 || return 0
    
    local flags=""
    [[ "$recursive" == "yes" ]] && flags="-R"
    
    chown $flags "$owner:$group" "$path" 2>/dev/null || true
    chmod $flags "$mode" "$path" 2>/dev/null || true
    
    # Apply SGID to subdirectories if mode starts with 2
    if [[ "$recursive" == "yes" && "$mode" =~ ^2 ]]; then
        find "$path" -type d -exec chmod g+s {} \; 2>/dev/null || true
    fi
}

_create_directories() {
    _conf_log_info "Creating share directories..."
    
    local indices dir_count=0
    indices=$(_get_share_indices)
    [[ -z "$indices" ]] && return 0
    
    local global_recursive
    global_recursive=$(_normalize_bool "${SHARE_RECURSIVE_OWNERSHIP:-no}" "no")
    
    while IFS= read -r i; do
        # FIXED: Define variable name BEFORE using indirect expansion
        local share_name_var="SHARE_NAME_$i"
        local share_name="${!share_name_var:-}"
        [[ -z "$share_name" ]] && continue
        
        local share_path="$_DATA_DIR/$share_name"
        
        # Create share directory
        if [[ ! -e "$share_path" ]]; then
            mkdir -p "$share_path"
            ((dir_count++))
        fi
        
        # Setup ownership
        local owner_var="SHARE_${i}_OWNER"
        local owner="${!owner_var:-}"
        if [[ -n "$owner" ]]; then
            local group_var="SHARE_${i}_OWNER_GROUP"
            local perms_var="SHARE_${i}_PERMISSION_MODE"
            local recursive_var="SHARE_${i}_RECURSIVE_OWNERSHIP"
            
            local group="${!group_var:-$owner}"
            local perms="${!perms_var:-2770}"
            local recursive="${!recursive_var:-$global_recursive}"
            recursive=$(_normalize_bool "$recursive" "no")
            
            _setup_permissions "$share_path" "$owner" "$group" "$perms" "$recursive"
        fi
        
        # Setup recycle bin
        local recycle_var="SHARE_${i}_RECYCLE_BIN"
        local recycle
        recycle=$(_normalize_bool "${!recycle_var:-no}" "no")
        
        if [[ "$recycle" == "yes" ]]; then
            local recycle_base="$share_path/.recycle"
            
            if [[ ! -e "$recycle_base" ]]; then
                mkdir -p "$recycle_base"
                ((dir_count++))
            fi
            
            local dir_mode_var="SHARE_${i}_RECYCLE_DIRECTORY_MODE"
            chmod "${!dir_mode_var:-0777}" "$recycle_base" 2>/dev/null || true
            
            # Create per-user directories
            local subdir_mode_var="SHARE_${i}_RECYCLE_SUB_DIRECTORY_MODE"
            local subdir_mode="${!subdir_mode_var:-0700}"
            
            local -a raw_entries=()
            for list_var in "SHARE_${i}_VALID_USERS" "SHARE_${i}_WRITE_LIST" "SHARE_${i}_READ_LIST"; do
                [[ -n "${!list_var:-}" ]] && IFS=' ' read -ra tmp <<< "${!list_var}" && raw_entries+=("${tmp[@]}")
            done
            
            # Expand @groups to get all users first
            local -a all_users=()
            for entry in "${raw_entries[@]}"; do
                if [[ "$entry" =~ ^@(.+)$ ]]; then
                    # It's a group - expand to members
                    local group_name="${BASH_REMATCH[1]}"
                    local group_entry
                    group_entry=$(getent group "$group_name" 2>/dev/null) || continue
                    local members="${group_entry##*:}"
                    if [[ -n "$members" ]]; then
                        IFS=',' read -ra grp_users <<< "$members"
                        all_users+=("${grp_users[@]}")
                    fi
                else
                    # It's a user
                    all_users+=("$entry")
                fi
            done
            
            # Create directories for unique valid users
            local processed=""
            for entry in "${all_users[@]}"; do
                [[ -z "$entry" || " $processed " =~ " $entry " ]] && continue
                [[ ! "$entry" =~ ^[a-zA-Z0-9._-]+$ ]] && continue
                processed="$processed $entry"
                
                if getent passwd "$entry" >/dev/null 2>&1; then
                    local user_dir="$recycle_base/$entry"
                    mkdir -p "$user_dir" 2>/dev/null || continue
                    chown "$entry:$entry" "$user_dir" 2>/dev/null || true
                    chmod "$subdir_mode" "$user_dir" 2>/dev/null || true
                    [[ ! -f "$user_dir/.initialized" ]] && touch "$user_dir/.initialized" && ((dir_count++))
                fi
            done
        fi
    done <<< "$indices"
    
    _conf_log_ok "Created $dir_count directories"
}

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================
_global_config() {
    _conf_log_info "Generating global configuration..."
    
    cat > "$_SMB_CONF" << 'EOF'
[global]
EOF

    # === Identity ===
    local netbios_name="${NETBIOS_NAME:-NASSERVER}"
    _write_conf "   netbios name = ${netbios_name:0:15}"
    _write_conf "   workgroup = ${SMB_WORKGROUP:-WORKGROUP}"
    _write_conf "   server string = ${SERVER_STRING:-Samba NAS Server}"
    
    # === Security Mode ===
    local security="${SECURITY_MODE:-user}"
    case "${security,,}" in
        user|share|ads|domain) _write_conf "   security = ${security,,}" ;;
        *) _write_conf "   security = user" ;;
    esac
    _write_conf "   passdb backend = ${PASSDB_BACKEND:-tdbsam}"
    _write_conf "   server role = ${SERVER_ROLE:-standalone server}"
    
    # === Protocol - SMB3_11 for maximum security (Android compatible) ===
    _write_conf "   server min protocol = ${SERVER_MIN_PROTOCOL:-SMB3_11}"
    [[ -n "${SERVER_MAX_PROTOCOL:-}" ]] && _write_conf "   server max protocol = $SERVER_MAX_PROTOCOL"
    _write_conf "   client min protocol = ${CLIENT_MIN_PROTOCOL:-SMB3_11}"
    [[ -n "${CLIENT_MAX_PROTOCOL:-}" ]] && _write_conf "   client max protocol = $CLIENT_MAX_PROTOCOL"
    
    # === Encryption (desired = Android compatible, required = breaks Android) ===
    local encrypt="${GLOBAL_ENCRYPT:-desired}"
    case "${encrypt,,}" in
        required|mandatory) encrypt="required" ;;
        desired|auto) encrypt="desired" ;;
        disabled|off|no) encrypt="disabled" ;;
        *) encrypt="desired" ;;
    esac
    GLOBAL_ENCRYPT="$encrypt"
    _write_conf "   smb encrypt = $encrypt"
    _write_conf "   server smb encrypt = $encrypt"
    _write_conf "   client smb encrypt = ${CLIENT_SMB_ENCRYPT:-$encrypt}"
    
    # Encryption algorithms (safe for Android)
    [[ -n "${SMB3_ENCRYPTION_ALGORITHMS:-}" ]] && {
        _write_conf "   server smb3 encryption algorithms = $SMB3_ENCRYPTION_ALGORITHMS"
        _write_conf "   client smb3 encryption algorithms = ${CLIENT_SMB3_ENCRYPTION_ALGORITHMS:-$SMB3_ENCRYPTION_ALGORITHMS}"
    }
    
    # === Signing (mandatory works with Android, but DO NOT set signing algorithms) ===
    local signing="${SERVER_SIGNING:-mandatory}"
    case "${signing,,}" in
        mandatory|required) signing="mandatory" ;;
        disabled|off) signing="disabled" ;;
        *) signing="default" ;;
    esac
    _write_conf "   server signing = $signing"
    
    local client_signing="${CLIENT_SIGNING:-mandatory}"
    case "${client_signing,,}" in
        mandatory|required) client_signing="mandatory" ;;
        disabled|off) client_signing="disabled" ;;
        *) client_signing="default" ;;
    esac
    _write_conf "   client signing = $client_signing"
    
    local ipc_signing="${CLIENT_IPC_SIGNING:-required}"
    case "${ipc_signing,,}" in
        required|mandatory) ipc_signing="required" ;;
        disabled|off) ipc_signing="disabled" ;;
        *) ipc_signing="auto" ;;
    esac
    _write_conf "   client ipc signing = $ipc_signing"
    
    # CRITICAL: DO NOT set SMB3 signing algorithms - breaks Android!
    
    # === Authentication ===
    local ntlm="${NTLM_AUTH:-ntlmv2-only}"
    case "${ntlm,,}" in
        disabled|no) ntlm="disabled" ;;
        ntlmv2-only|ntlmv2) ntlm="ntlmv2-only" ;;
        ntlmv1-permitted|yes) ntlm="ntlmv1-permitted" ;;
        *) ntlm="ntlmv2-only" ;;
    esac
    _write_conf "   ntlm auth = $ntlm"
    _write_conf "   lanman auth = $(_normalize_bool "${LANMAN_AUTH:-no}" "no")"
    _write_conf "   client ntlmv2 auth = $(_normalize_bool "${CLIENT_NTLMV2_AUTH:-yes}" "yes")"
    _write_conf "   client lanman auth = $(_normalize_bool "${CLIENT_LANMAN_AUTH:-no}" "no")"
    _write_conf "   client plaintext auth = $(_normalize_bool "${CLIENT_PLAINTEXT_AUTH:-no}" "no")"
    
    local restrict="${RESTRICT_ANONYMOUS:-2}"
    restrict=$(_validate_numeric "$restrict" 2>/dev/null) || restrict=2
    [[ "$restrict" -ge 0 && "$restrict" -le 2 ]] && _write_conf "   restrict anonymous = $restrict"
    _write_conf "   null passwords = $(_normalize_bool "${NULL_PASSWORDS:-no}" "no")"
    
    # === Networking (NetBIOS disabled by default - not needed for Android) ===
    [[ -n "${SAMBA_INTERFACES:-}" ]] && _write_conf "   interfaces = $SAMBA_INTERFACES"
    _write_conf "   bind interfaces only = $(_normalize_bool "${BIND_INTERFACES_ONLY:-no}" "no")"
    
    local disable_netbios
    disable_netbios=$(_normalize_bool "${DISABLE_NETBIOS:-yes}" "yes")
    local smb_port
    smb_port=$(_validate_numeric "${SMB_PORT:-445}" 2>/dev/null) || smb_port=445
    
    _write_conf "   disable netbios = $disable_netbios"
    if [[ "$disable_netbios" == "yes" ]]; then
        _write_conf "   smb ports = $smb_port"
    else
        local netbios_port
        netbios_port=$(_validate_numeric "${NETBIOS_PORT:-139}" 2>/dev/null) || netbios_port=139
        _write_conf "   smb ports = $smb_port $netbios_port"
    fi
    
    # === Network Services (all disabled for NAS) ===
    _write_conf "   wins support = $(_normalize_bool "${WINS_SUPPORT:-no}" "no")"
    _write_conf "   local master = $(_normalize_bool "${LOCAL_MASTER:-no}" "no")"
    _write_conf "   preferred master = $(_normalize_bool "${PREFERRED_MASTER:-no}" "no")"
    _write_conf "   domain master = $(_normalize_bool "${DOMAIN_MASTER:-no}" "no")"
    _write_conf "   dns proxy = $(_normalize_bool "${DNS_PROXY:-no}" "no")"
    
    # === Logging (default 0 for production - higher levels impact performance) ===
    local log_level
    log_level=$(_validate_numeric "${LOG_LEVEL:-0}" 2>/dev/null) || log_level=0
    [[ "$log_level" -ge 0 && "$log_level" -le 10 ]] && _write_conf "   log level = $log_level"
    
    local max_log
    max_log=$(_validate_numeric "${MAX_LOG_SIZE:-50000}" 2>/dev/null) || max_log=50000
    _write_conf "   max log size = $max_log"
    _write_conf "   log file = ${SAMBA_LOG_FILE:-/var/log/samba/%m.log}"
    _write_conf "   logging = ${LOGGING:-file}"
    _write_conf "   debug timestamp = $(_normalize_bool "${DEBUG_TIMESTAMP:-yes}" "yes")"
    _write_conf "   debug pid = $(_normalize_bool "${DEBUG_PID:-yes}" "yes")"
    _write_conf "   debug uid = $(_normalize_bool "${DEBUG_UID:-yes}" "yes")"
    
    # === Directories ===
    _write_conf "   lock dir = $_LOCK_DIR"
    _write_conf "   pid directory = $_PID_DIR"
    _write_conf "   private dir = $_PRIVATE_DIR"
    _write_conf "   state directory = $_STATE_DIR"
    _write_conf "   cache directory = $_CACHE_DIR"
    
    # === Name Resolution ===
    _write_conf "   name resolve order = ${NAME_RESOLVE_ORDER:-bcast host lmhosts wins}"
    
    # === Guest Mapping ===
    local map_guest="${MAP_TO_GUEST:-Never}"
    case "${map_guest,,}" in
        "bad user"|baduser) _write_conf "   map to guest = Bad User" ;;
        "bad password"|badpassword) _write_conf "   map to guest = Bad Password" ;;
        *) _write_conf "   map to guest = Never" ;;
    esac
    [[ -e "$_GUEST_ACC" ]] && _write_conf "   guest account = ${GUEST_ACCOUNT:-guest}"
    
    # === Performance (optimized for high-scale: 1000+ clients) ===
    _write_conf "   use sendfile = $(_normalize_bool "${USE_SENDFILE:-yes}" "yes")"
    
    local min_recv aio_read aio_write max_xmit
    min_recv=$(_validate_numeric "${MIN_RECEIVEFILE_SIZE:-16384}" 2>/dev/null) || min_recv=16384
    # AIO: 1 = always async (best for large files), 0 = sync (may be better for many small files)
    aio_read=$(_validate_numeric "${AIO_READ_SIZE:-1}" 2>/dev/null) || aio_read=1
    aio_write=$(_validate_numeric "${AIO_WRITE_SIZE:-1}" 2>/dev/null) || aio_write=1
    max_xmit=$(_validate_numeric "${MAX_XMIT:-65535}" 2>/dev/null) || max_xmit=65535
    
    _write_conf "   min receivefile size = $min_recv"
    _write_conf "   aio read size = $aio_read"
    _write_conf "   aio write size = $aio_write"
    _write_conf "   read raw = $(_normalize_bool "${READ_RAW:-yes}" "yes")"
    _write_conf "   write raw = $(_normalize_bool "${WRITE_RAW:-yes}" "yes")"
    _write_conf "   large readwrite = $(_normalize_bool "${LARGE_READWRITE:-yes}" "yes")"
    [[ "$max_xmit" -ge 1024 && "$max_xmit" -le 65535 ]] && _write_conf "   max xmit = $max_xmit"
    
    # SSD/Filesystem optimization - align allocations to block size
    local alloc_roundup
    alloc_roundup=$(_validate_numeric "${ALLOCATION_ROUNDUP_SIZE:-4096}" 2>/dev/null) || alloc_roundup=4096
    _write_conf "   allocation roundup size = $alloc_roundup"
    
    # === SMB2/3 Performance (enterprise-scale, optimized for both SMB2 & SMB3) ===
    # Max credits: Higher = more parallel operations per client
    # Range: 128-65535, default 8192 is conservative
    # For 50+ connections per client, use maximum
    local smb2_credits
    smb2_credits=$(_validate_numeric "${SMB2_MAX_CREDITS:-65535}" 2>/dev/null) || smb2_credits=65535
    [[ "$smb2_credits" -ge 128 && "$smb2_credits" -le 65535 ]] && \
        _write_conf "   smb2 max credits = $smb2_credits"
    
    # SMB2/3 buffer sizes: Maximum allowed by protocol
    # 16MB (16777216) is the SMB2/3 protocol maximum
    local smb2_max_read smb2_max_write smb2_max_trans
    smb2_max_read=$(_validate_numeric "${SMB2_MAX_READ:-16777216}" 2>/dev/null) || smb2_max_read=16777216
    smb2_max_write=$(_validate_numeric "${SMB2_MAX_WRITE:-16777216}" 2>/dev/null) || smb2_max_write=16777216
    smb2_max_trans=$(_validate_numeric "${SMB2_MAX_TRANS:-16777216}" 2>/dev/null) || smb2_max_trans=16777216
    
    _write_conf "   smb2 max read = $smb2_max_read"
    _write_conf "   smb2 max write = $smb2_max_write"
    _write_conf "   smb2 max trans = $smb2_max_trans"
    
    _write_conf "   server multi channel support = $(_normalize_bool "${SERVER_MULTI_CHANNEL_SUPPORT:-yes}" "yes")"
    
    # === Connection Management ===
    local keepalive deadtime
    keepalive=$(_validate_numeric "${KEEPALIVE:-300}" 2>/dev/null) || keepalive=300
    deadtime=$(_validate_numeric "${DEADTIME:-15}" 2>/dev/null) || deadtime=15
    _write_conf "   keepalive = $keepalive"
    _write_conf "   deadtime = $deadtime"
    _write_conf "   getwd cache = $(_normalize_bool "${GETWD_CACHE:-yes}" "yes")"
    
    # === HIGH-SCALE CONNECTION SETTINGS (50K+ simultaneous connections) ===
    local max_connections max_smbd
    max_connections=$(_validate_numeric "${MAX_CONNECTIONS:-0}" 2>/dev/null) || max_connections=0
    max_smbd=$(_validate_numeric "${MAX_SMBD_PROCESSES:-0}" 2>/dev/null) || max_smbd=0
    
    # 0 = unlimited (required for high-scale deployments)
    _write_conf "   max connections = $max_connections"
    [[ "$max_smbd" -gt 0 ]] && _write_conf "   max smbd processes = $max_smbd"
    
    # Durable handles for reconnection stability
    _write_conf "   durable handles = $(_normalize_bool "${DURABLE_HANDLES:-yes}" "yes")"
    
    # CRITICAL: kernel share modes and posix locking cause browsing to lock files
    # DISABLED by default for multi-client compatibility (Android/Windows/Linux)
    _write_conf "   kernel share modes = $(_normalize_bool "${KERNEL_SHARE_MODES:-no}" "no")"
    _write_conf "   posix locking = $(_normalize_bool "${POSIX_LOCKING:-no}" "no")"
    
    # SMB2/3 leases - DISABLED by default for multi-client compatibility
    # Leases cause client-side caching that blocks other clients from opening files
    _write_conf "   smb2 leases = $(_normalize_bool "${SMB2_LEASES:-no}" "no")"
    
    # Async operations for better throughput under high load
    _write_conf "   async smb echo handler = $(_normalize_bool "${ASYNC_SMB_ECHO:-yes}" "yes")"
    
    # Connection caching (higher for enterprise scale)
    local conn_cache
    conn_cache=$(_validate_numeric "${CONN_CACHE_COUNT:-10000}" 2>/dev/null) || conn_cache=10000
    _write_conf "   conn cache count = $conn_cache"
    
    # Max mux - maximum simultaneous operations per connection
    local max_mux
    max_mux=$(_validate_numeric "${MAX_MUX:-50}" 2>/dev/null) || max_mux=50
    _write_conf "   max mux = $max_mux"
    
    # === Locking & Oplocks ===
    # ALL DISABLED by default for multi-client compatibility
    # Oplocks/leases cause aggressive client-side caching which prevents
    # other clients from opening files. Directory browsing alone can lock files.
    # Set OPLOCKS=yes ONLY if you have single-client access and need max performance.
    _write_conf "   strict locking = $(_normalize_bool "${STRICT_LOCKING:-no}" "no")"
    _write_conf "   oplocks = $(_normalize_bool "${OPLOCKS:-no}" "no")"
    _write_conf "   level2 oplocks = $(_normalize_bool "${LEVEL2_OPLOCKS:-no}" "no")"
    _write_conf "   kernel oplocks = $(_normalize_bool "${KERNEL_OPLOCKS:-no}" "no")"
    
    # Blocking locks - disable to prevent hangs
    _write_conf "   blocking locks = $(_normalize_bool "${BLOCKING_LOCKS:-no}" "no")"
    
    # Lock spin settings for high contention scenarios
    local lock_spin_time lock_spin_count
    lock_spin_time=$(_validate_numeric "${LOCK_SPIN_TIME:-200}" 2>/dev/null) || lock_spin_time=200
    lock_spin_count=$(_validate_numeric "${LOCK_SPIN_COUNT:-3}" 2>/dev/null) || lock_spin_count=3
    _write_conf "   lock spin time = $lock_spin_time"
    _write_conf "   lock spin count = $lock_spin_count"
    
    # === Host Access ===
    [[ -n "${HOSTS_ALLOW:-}" ]] && _write_conf "   hosts allow = $HOSTS_ALLOW"
    [[ -n "${HOSTS_DENY:-}" ]] && _write_conf "   hosts deny = $HOSTS_DENY"
    
    # === Unix/Filesystem ===
    _write_conf "   unix extensions = $(_normalize_bool "${UNIX_EXTENSIONS:-yes}" "yes")"
    _write_conf "   wide links = $(_normalize_bool "${WIDE_LINKS:-no}" "no")"
    _write_conf "   follow symlinks = $(_normalize_bool "${FOLLOW_SYMLINKS:-yes}" "yes")"
    _write_conf "   create mask = ${CREATE_MASK:-0664}"
    _write_conf "   directory mask = ${DIRECTORY_MASK:-0775}"
    _write_conf "   dont descend = /proc,/dev,/etc,/lib,/lost+found,/initrd"
    
    # === File Attributes ===
    _write_conf "   store dos attributes = $(_normalize_bool "${STORE_DOS_ATTRIBUTES:-yes}" "yes")"
    _write_conf "   map archive = $(_normalize_bool "${MAP_ARCHIVE:-no}" "no")"
    _write_conf "   map system = $(_normalize_bool "${MAP_SYSTEM:-no}" "no")"
    _write_conf "   map hidden = $(_normalize_bool "${MAP_HIDDEN:-no}" "no")"
    
    # === Character Encoding ===
    _write_conf "   unix charset = ${UNIX_CHARSET:-UTF-8}"
    _write_conf "   dos charset = ${DOS_CHARSET:-CP850}"
    _write_conf "   mangled names = $(_normalize_bool "${MANGLED_NAMES:-no}" "no")"
    
    # === Printing (disabled for NAS) ===
    _write_conf "   load printers = $(_normalize_bool "${LOAD_PRINTERS:-no}" "no")"
    _write_conf "   printing = ${PRINTING:-bsd}"
    _write_conf "   printcap name = ${PRINTCAP_NAME:-/dev/null}"
    _write_conf "   disable spoolss = $(_normalize_bool "${DISABLE_SPOOLSS:-yes}" "yes")"
    
    # === Misc (enterprise scale) ===
    local max_files
    max_files=$(_validate_numeric "${MAX_OPEN_FILES:-100000}" 2>/dev/null) || max_files=100000
    _write_conf "   max open files = $max_files"
    _write_conf "   nt pipe support = $(_normalize_bool "${NT_PIPE_SUPPORT:-yes}" "yes")"
    _write_conf "   panic action = ${PANIC_ACTION:-/usr/lib/samba/panic-action %d}"
    
    # === CRITICAL: Socket Options ===
    # Per Samba Wiki: Modern kernels auto-tune TCP buffers. Setting socket_options
    # DECREASES performance in most cases. Only set if you have specific requirements.
    # DO NOT USE: socket options = TCP_NODELAY (already default since Samba 2.0.4)
    [[ -n "${SOCKET_OPTIONS:-}" ]] && _write_conf "   socket options = $SOCKET_OPTIONS"
    
    # === Name Resolution (optimized for pure SMB2/3 environments) ===
    _write_conf "   name resolve order = ${NAME_RESOLVE_ORDER:-lmhosts wins host bcast}"
    
    # === Sync Settings (NEVER enable sync always in production - kills performance) ===
    _write_conf "   sync always = $(_normalize_bool "${SYNC_ALWAYS:-no}" "no")"
    _write_conf "   strict sync = $(_normalize_bool "${STRICT_SYNC:-no}" "no")"
    
    # === macOS Support ===
    if [[ "$(_normalize_bool "${ENABLE_MACOS_OPTS:-yes}" "yes")" == "yes" ]]; then
        BASE_VFS_MODULES="catia fruit streams_xattr"
        _write_conf "   fruit:aapl = yes"
        _write_conf "   fruit:copyfile = yes"
        _write_conf "   fruit:nfs_aces = no"
        _write_conf "   fruit:metadata = stream"
        _write_conf "   fruit:model = MacSamba"
        _write_conf "   fruit:posix_rename = yes"
        _write_conf "   fruit:veto_appledouble = no"
        _write_conf "   fruit:wipe_intentionally_left_blank_rfork = yes"
        _write_conf "   fruit:delete_empty_adfiles = yes"
    fi
}

# ============================================================================
# SHARE CONFIGURATION
# ============================================================================
_enable_guest() {
    [[ -e "$_GUEST_ACC" ]] || touch "$_GUEST_ACC"
}

_configure_share() {
    local i=$1
    local share_name_var="SHARE_NAME_$i"
    local share_name="${!share_name_var:-}"
    
    [[ -z "$share_name" ]] && return 1
    
    _write_conf ""
    _write_conf "[$share_name]"
    
    local comment_var="SHARE_${i}_COMMENT"
    [[ -n "${!comment_var:-}" ]] && _write_conf "   comment = ${!comment_var}"
    
    _write_conf "   path = $_DATA_DIR/$share_name"
    
    # Per-share encryption (only if global is auto)
    if [[ "${GLOBAL_ENCRYPT:-}" == "auto" ]]; then
        local encrypt_var="SHARE_${i}_ENCRYPT"
        local share_encrypt="${!encrypt_var:-auto}"
        case "${share_encrypt,,}" in
            required|mandatory|yes) share_encrypt="required" ;;
            disabled|off|no) share_encrypt="disabled" ;;
            *) share_encrypt="auto" ;;
        esac
        _write_conf "   server smb encrypt = $share_encrypt"
    fi
    
    # Extended attributes
    local ea_var="SHARE_${i}_ENABLE_EXTENDED_ATTRIBUTE"
    _write_conf "   ea support = $(_normalize_bool "${!ea_var:-yes}" "yes")"
    
    local dos_var="SHARE_${i}_ENABLE_DOS_ATTRIBUTE"
    _write_conf "   store dos attributes = $(_normalize_bool "${!dos_var:-yes}" "yes")"
    
    # Users
    local valid_users_var="SHARE_${i}_VALID_USERS"
    [[ -n "${!valid_users_var:-}" ]] && _write_conf "   valid users = ${!valid_users_var}"
    
    # Guest access
    local guest_ok_var="SHARE_${i}_GUEST_OK"
    local public_var="SHARE_${i}_PUBLIC"
    local guest_ok public
    guest_ok=$(_normalize_bool "${!guest_ok_var:-no}" "no")
    public=$(_normalize_bool "${!public_var:-no}" "no")
    
    [[ "$guest_ok" == "yes" ]] && { public="yes"; _enable_guest; }
    _write_conf "   public = $public"
    
    local guest_only_var="SHARE_${i}_GUEST_ONLY"
    local guest_only
    guest_only=$(_normalize_bool "${!guest_only_var:-no}" "no")
    [[ "$guest_only" == "yes" && -z "${!valid_users_var:-}" ]] && _enable_guest || guest_only="no"
    _write_conf "   guest only = $guest_only"
    
    # Browseable
    local browseable_var="SHARE_${i}_BROWSEABLE"
    _write_conf "   browseable = $(_normalize_bool "${!browseable_var:-yes}" "yes")"
    
    # Read/Write
    local read_only_var="SHARE_${i}_READ_ONLY"
    local writeable_var="SHARE_${i}_WRITEABLE"
    local read_only writeable
    read_only=$(_normalize_bool "${!read_only_var:-yes}" "yes")
    writeable=$(_normalize_bool "${!writeable_var:-no}" "no")
    [[ "$read_only" == "no" || "$writeable" == "yes" ]] && writeable="yes" || writeable="no"
    _write_conf "   writable = $writeable"
    
    # Access lists
    local read_list_var="SHARE_${i}_READ_LIST"
    local write_list_var="SHARE_${i}_WRITE_LIST"
    [[ -n "${!read_list_var:-}" ]] && _write_conf "   read list = ${!read_list_var}"
    [[ -n "${!write_list_var:-}" ]] && _write_conf "   write list = ${!write_list_var}"
    
    # Permissions
    local create_mask_var="SHARE_${i}_CREATE_MASK"
    local force_create_var="SHARE_${i}_FORCE_CREATE_MASK"
    local dir_mask_var="SHARE_${i}_DIRECTORY_MASK"
    local force_dir_var="SHARE_${i}_FORCE_DIRECTORY_MASK"
    
    [[ -n "${!create_mask_var:-}" ]] && _write_conf "   create mask = ${!create_mask_var}"
    [[ -n "${!force_create_var:-}" ]] && _write_conf "   force create mode = ${!force_create_var}"
    [[ -n "${!dir_mask_var:-}" ]] && _write_conf "   directory mask = ${!dir_mask_var}"
    [[ -n "${!force_dir_var:-}" ]] && _write_conf "   force directory mode = ${!force_dir_var}"
    
    # Force user/group
    local force_user_var="SHARE_${i}_FORCE_USER"
    local force_group_var="SHARE_${i}_FORCE_GROUP"
    [[ -n "${!force_user_var:-}" ]] && _write_conf "   force user = ${!force_user_var}"
    [[ -n "${!force_group_var:-}" ]] && _write_conf "   force group = ${!force_group_var}"
    
    # VFS modules
    local recycle_var="SHARE_${i}_RECYCLE_BIN"
    local btrfs_var="SHARE_${i}_IS_BTRFS"
    local recycle btrfs vfs_modules
    
    recycle=$(_normalize_bool "${!recycle_var:-no}" "no")
    btrfs=$(_normalize_bool "${!btrfs_var:-no}" "no")
    
    vfs_modules="${BASE_VFS_MODULES:-}"
    [[ "$recycle" == "yes" ]] && vfs_modules="$vfs_modules recycle"
    [[ "$btrfs" == "yes" ]] && vfs_modules="$vfs_modules btrfs"
    
    _write_conf "   vfs objects = $vfs_modules"
    
    # Recycle bin config
    if [[ "$recycle" == "yes" ]]; then
        local dir_mode_var="SHARE_${i}_RECYCLE_DIRECTORY_MODE"
        local subdir_mode_var="SHARE_${i}_RECYCLE_SUB_DIRECTORY_MODE"
        local max_size_var="SHARE_${i}_RECYCLE_MAX_SIZE"
        
        _write_conf "   recycle:repository = $_DATA_DIR/$share_name/.recycle/%U"
        _write_conf "   recycle:keeptree = yes"
        _write_conf "   recycle:versions = yes"
        _write_conf "   recycle:touch = yes"
        _write_conf "   recycle:touch_mtime = no"
        _write_conf "   recycle:directory_mode = ${!dir_mode_var:-0777}"
        _write_conf "   recycle:subdir_mode = ${!subdir_mode_var:-0700}"
        [[ -n "${!max_size_var:-}" ]] && _write_conf "   recycle:maxsize = ${!max_size_var}"
        _write_conf "   recycle:exclude = "
        _write_conf "   recycle:exclude_dir = .recycle"
    fi
}

_configure_temp_share() {
    [[ "$(_normalize_bool "${TEMP_SHARE_ON:-no}" "no")" != "yes" ]] && return
    
    local name="${TEMP_SHARE_NAME:-temp-share}"
    
    _write_conf ""
    _write_conf "[${name}]"
    _write_conf "   path = $_DATA_DIR/$name"
    [[ -n "${TEMP_SHARE_COMMENT:-}" ]] && _write_conf "   comment = $TEMP_SHARE_COMMENT"
    _write_conf "   read only = $(_normalize_bool "${TEMP_SHARE_READ_ONLY:-no}" "no")"
    _write_conf "   public = $(_normalize_bool "${TEMP_SHARE_PUBLIC:-yes}" "yes")"
    
    local recycle vfs_modules
    recycle=$(_normalize_bool "${TEMP_RECYCLE_BIN:-no}" "no")
    vfs_modules="${BASE_VFS_MODULES:-}"
    [[ "$recycle" == "yes" ]] && vfs_modules="$vfs_modules recycle"
    
    _write_conf "   vfs objects = $vfs_modules"
    
    if [[ "$recycle" == "yes" ]]; then
        _write_conf "   recycle:repository = $_DATA_DIR/$name/.recycle/%U"
        _write_conf "   recycle:keeptree = yes"
        _write_conf "   recycle:versions = yes"
        _write_conf "   recycle:touch = yes"
        _write_conf "   recycle:touch_mtime = no"
        _write_conf "   recycle:directory_mode = ${TEMP_RECYCLE_DIRECTORY_MODE:-0777}"
        _write_conf "   recycle:subdir_mode = ${TEMP_RECYCLE_SUB_DIRECTORY_MODE:-0700}"
        [[ -n "${TEMP_RECYCLE_MAX_SIZE:-}" ]] && _write_conf "   recycle:maxsize = $TEMP_RECYCLE_MAX_SIZE"
        _write_conf "   recycle:exclude = "
        _write_conf "   recycle:exclude_dir = .recycle"
    fi
}

_validate_config() {
    _conf_log_info "Validating configuration..."
    
    if ! command -v testparm &>/dev/null; then
        _conf_error_exit "testparm not found"
    fi
    
    if testparm -s "$_SMB_CONF" >/dev/null 2>&1; then
        _conf_log_ok "Configuration valid"
    else
        _conf_error_exit "Invalid configuration - run 'testparm $_SMB_CONF'"
    fi
}

# ============================================================================
# MAIN
# ============================================================================
_conf_main() {
    _conf_log_info "=== Samba Configuration v$_CONF_SCRIPT_VERSION ==="
    
    _create_directories
    _validate_references
    _global_config
    
    _write_conf ""
    _write_conf "#============================ SHARE DEFINITIONS ============================"
    
    local indices
    indices=$(_get_share_indices)
    
    if [[ -n "$indices" ]]; then
        while IFS= read -r i; do
            _configure_share "$i" || continue
        done <<< "$indices"
    fi
    
    _configure_temp_share
    
    _write_conf ""
    _write_conf "#============================ END CONFIGURATION ============================"
    
    _validate_config
    
    _conf_log_ok "Configuration complete: $_SMB_CONF"
}

# Run main only if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _conf_main "$@"
else
    # When sourced, just run main
    _conf_main "$@"
fi
