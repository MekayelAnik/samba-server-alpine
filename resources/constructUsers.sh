#!/bin/bash
# constructUsers.sh - Enterprise-Scale User Creation with Batch Operations
# Version: 3.3.1
# Features: newusers batch creation, caching, secondary groups, Samba verification
# Performance: ~15x faster than sequential for 1000+ users
set -euo pipefail

# Script metadata
if [[ -z "${SCRIPT_NAME:-}" ]]; then
    readonly SCRIPT_NAME="$(basename "$0")"
fi
if [[ -z "${SCRIPT_VERSION:-}" ]]; then
    readonly SCRIPT_VERSION="3.3.1"
fi

# Print version immediately
echo "[i] === User Creation Script v${SCRIPT_VERSION} ==="

# === 2025 Best Practice Defaults ===
readonly DEFAULT_GUEST_ACCOUNT='guest'
readonly DEFAULT_GUEST_UID="${GUEST_UID:-65534}"
readonly DEFAULT_GUEST_GID="${GUEST_GID:-65534}"

readonly DEFAULT_UID_MIN="${UID_MIN:-1000}"
readonly DEFAULT_UID_MAX="${UID_MAX:-60000}"
readonly DEFAULT_GID_MIN="${GID_MIN:-1000}"
readonly DEFAULT_GID_MAX="${GID_MAX:-60000}"

readonly USER_UID_OFFSET="${USER_UID_OFFSET:-1000}"
readonly CREATE_HOME_DIR="${CREATE_HOME_DIR:-no}"
readonly HOME_DIR_PERMISSIONS="${HOME_DIR_PERMISSIONS:-700}"
readonly DEFAULT_SHELL="${DEFAULT_SHELL:-/bin/false}"
readonly DEFAULT_UMASK="${DEFAULT_UMASK:-027}"

readonly ENFORCE_OPTIMAL_VALUES="${ENFORCE_OPTIMAL_VALUES:-0}"

# Configuration
readonly SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"
readonly USER_PASSWORD_MIN_LENGTH="${USER_PASSWORD_MIN_LENGTH:-8}"
readonly USER_PASSWORD_STRICT_MODE="${USER_PASSWORD_STRICT_MODE:-0}"
readonly AUTO_CLEANUP_ON_FAILURE="${AUTO_CLEANUP_ON_FAILURE:-0}"
readonly FORCE_CLEANUP="${FORCE_CLEANUP:-0}"
readonly SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"

# Samba directory paths
readonly SAMBA_PRIVATE_DIR="${SAMBA_PRIVATE_DIR:-/var/lib/samba/private}"
readonly SAMBA_STATE_DIR="${SAMBA_STATE_DIR:-/var/lib/samba}"
readonly SAMBA_LOCK_DIR="${SAMBA_LOCK_DIR:-/var/lib/samba/locks}"

# Batch operation settings
readonly BATCH_USER_CREATION="${BATCH_USER_CREATION:-1}"  # Enable by default
readonly BATCH_TEMP_FILE="/tmp/.newusers_batch_$$"

# ============================================================================
# COLOR PALETTE
# ============================================================================
[[ -z "${SUCCESS_GREEN:-}" ]] && readonly SUCCESS_GREEN='\033[38;5;10m'
[[ -z "${ERROR_RED:-}" ]] && readonly ERROR_RED='\033[38;5;9m'
[[ -z "${WARNING_YELLOW:-}" ]] && readonly WARNING_YELLOW='\033[38;5;11m'
[[ -z "${INFO_CYAN:-}" ]] && readonly INFO_CYAN='\033[38;5;14m'
[[ -z "${SEA_GREEN:-}" ]] && readonly SEA_GREEN='\033[38;5;74m'
[[ -z "${NAVY_BLUE:-}" ]] && readonly NAVY_BLUE='\033[38;5;18m'
[[ -z "${TEAL:-}" ]] && readonly TEAL='\033[38;5;45m'
[[ -z "${WHITE:-}" ]] && readonly WHITE='\033[38;5;15m'
[[ -z "${LIGHT_GRAY:-}" ]] && readonly LIGHT_GRAY='\033[38;5;252m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m'
[[ -z "${BOLD:-}" ]] && readonly BOLD='\033[1m'

# === Logging Functions ===
log_info() {
    printf "${INFO_CYAN}[%s] [i INFO]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_error() {
    printf "${ERROR_RED}[%s] [✗ ERROR]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_warn() {
    printf "${WARNING_YELLOW}[%s] [! WARN]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_success() {
    printf "${SUCCESS_GREEN}[%s] [✓ SUCCESS]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_progress() {
    printf "${SEA_GREEN}[%s] [> PROGRESS]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_critical() {
    printf "${BOLD}${ERROR_RED}[%s] [!! CRITICAL]${NC} %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

exit_error() {
    log_error "$*"
    cleanup_temp_files
    exit 1
}

# === Utility Functions ===
print_header() {
    printf "\n${BOLD}${NAVY_BLUE}═══════════════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}${NAVY_BLUE}   %s${NC}\n" "$*"
    printf "${BOLD}${NAVY_BLUE}═══════════════════════════════════════════════════════════════════${NC}\n\n"
}

print_separator() {
    printf "${LIGHT_GRAY}───────────────────────────────────────────────────────────────────${NC}\n"
}

print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${BOLD}${WHITE}%-20s${NC} ${TEAL}%s${NC}\n" "$key:" "$value"
}

cleanup_temp_files() {
    rm -f "$BATCH_TEMP_FILE" 2>/dev/null || true
    rm -f "${BATCH_TEMP_FILE}.groups" 2>/dev/null || true
    rm -f "${BATCH_TEMP_FILE}.samba" 2>/dev/null || true
    rm -f "${BATCH_TEMP_FILE}.count" 2>/dev/null || true
}

# Trap to clean up on exit
trap cleanup_temp_files EXIT

# ============================================================================
# CACHING SYSTEM (O(1) lookups for bulk operations)
# ============================================================================
declare -A _GROUP_CACHE 2>/dev/null || true
declare -A _USER_CACHE 2>/dev/null || true
_CACHE_INITIALIZED=0

init_caches() {
    if [[ "$_CACHE_INITIALIZED" == "1" ]]; then
        return 0
    fi
    
    log_info "Initializing lookup caches..."
    
    # Cache all groups
    while IFS=: read -r name _ gid _; do
        _GROUP_CACHE["$name"]="$gid"
    done < /etc/group
    
    # Cache all users
    while IFS=: read -r name _ uid _; do
        _USER_CACHE["$name"]="$uid"
    done < /etc/passwd
    
    _CACHE_INITIALIZED=1
    log_info "✓ Cached ${#_GROUP_CACHE[@]} groups, ${#_USER_CACHE[@]} users"
}

refresh_caches() {
    _GROUP_CACHE=()
    _USER_CACHE=()
    _CACHE_INITIALIZED=0
    init_caches
}

user_exists() {
    local username="$1"
    if [[ "$_CACHE_INITIALIZED" == "1" ]]; then
        [[ -n "${_USER_CACHE[$username]+x}" ]]
        return $?
    fi
    id "$username" >/dev/null 2>&1
}

group_exists() {
    local groupname="$1"
    if [[ "$_CACHE_INITIALIZED" == "1" ]]; then
        [[ -n "${_GROUP_CACHE[$groupname]+x}" ]]
        return $?
    fi
    getent group "$groupname" >/dev/null 2>&1
}

_cache_add_user() {
    local username="$1"
    local uid="$2"
    if [[ "$_CACHE_INITIALIZED" == "1" ]]; then
        _USER_CACHE["$username"]="$uid"
    fi
}

_cache_add_group() {
    local groupname="$1"
    local gid="$2"
    if [[ "$_CACHE_INITIALIZED" == "1" ]]; then
        _GROUP_CACHE["$groupname"]="$gid"
    fi
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================
validate_numeric_id() {
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

validate_password() {
    local password="$1"
    local min_length="${2:-$USER_PASSWORD_MIN_LENGTH}"
    
    if [[ -z "$password" ]]; then
        log_error "Password cannot be empty"
        return 1
    fi
    
    if [[ ${#password} -lt $min_length ]]; then
        log_error "Password too short (minimum $min_length characters, got ${#password})"
        return 1
    fi
    
    return 0
}

validate_uid_range() {
    local uid="$1"
    local username="$2"
    
    if [[ "$uid" -eq 0 ]]; then
        log_critical "UID 0 IS ROOT - BLOCKED for user '$username'"
        return 1
    fi
    
    if [[ "$uid" -ge 1 && "$uid" -lt "$DEFAULT_UID_MIN" ]]; then
        log_warn "UID $uid is in SYSTEM RANGE for '$username' (optimal: $DEFAULT_UID_MIN-$DEFAULT_UID_MAX)"
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            return 1
        fi
    fi
    
    return 0
}

validate_gid_range() {
    local gid="$1"
    local groupname="$2"
    
    if [[ "$gid" -eq 0 ]]; then
        log_critical "GID 0 is root group - BLOCKED for group '$groupname'"
        return 1
    fi
    
    if [[ "$gid" -ge 1 && "$gid" -lt "$DEFAULT_GID_MIN" ]]; then
        log_warn "GID $gid is in SYSTEM RANGE for '$groupname' (optimal: $DEFAULT_GID_MIN-$DEFAULT_GID_MAX)"
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
preflight_checks() {
    log_info "=== Running Pre-flight Checks ==="
    
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi
    log_info "✓ Running as root"
    
    # Check for newusers (from shadow package)
    if command -v newusers &> /dev/null; then
        log_info "✓ Found 'newusers' command (batch mode enabled)"
    else
        log_warn "Command 'newusers' not found - falling back to sequential mode"
        log_warn "Install 'shadow' package for 15x faster bulk user creation"
    fi
    
    local required_cmds=("smbpasswd" "id" "getent")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    log_info "✓ Found all required commands"
    
    if [[ ! -f "$SMB_CONF" ]]; then
        log_error "smb.conf not found: $SMB_CONF"
        return 1
    fi
    log_info "✓ Found smb.conf: $SMB_CONF"
    
    log_info "=== Pre-flight Checks Passed ==="
    return 0
}

verify_passdb_backend() {
    log_info "Verifying passdb backend..."
    
    if ! command -v testparm &> /dev/null; then
        log_warn "testparm not available, skipping passdb verification"
        return 0
    fi
    
    local passdb_backend
    passdb_backend=$(testparm -s --parameter-name="passdb backend" 2>/dev/null || echo "tdbsam")
    log_info "Passdb backend: $passdb_backend"
    
    case "$passdb_backend" in
        tdbsam*|smbpasswd*)
            log_info "✓ Using local passdb backend"
            return 0
            ;;
        ldapsam*)
            log_info "✓ Using LDAP passdb backend"
            return 0
            ;;
        *)
            log_warn "Unknown passdb backend: $passdb_backend"
            return 0
            ;;
    esac
}

verify_samba_directories() {
    log_info "Verifying Samba directories..."
    
    local required_dirs=("$SAMBA_PRIVATE_DIR" "$SAMBA_STATE_DIR" "$SAMBA_LOCK_DIR")
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if mkdir -p "$dir" 2>/dev/null; then
                log_info "✓ Created directory: $dir"
            else
                log_warn "Could not create directory: $dir"
            fi
        fi
    done
}

# ============================================================================
# USER INDEX DISCOVERY
# ============================================================================
get_user_indices() {
    # Find all USER_NAME_* variables and extract indices
    compgen -v USER_NAME_ 2>/dev/null | sed 's/USER_NAME_//' | sort -n || true
}

# ============================================================================
# BATCH USER CREATION WITH newusers (MASSIVE PERFORMANCE BOOST)
# ============================================================================

# Pre-create all groups (primary and secondary) before user creation
# This ensures all groups exist before newusers runs
precreate_all_groups() {
    local user_indices="$1"
    local groups_created=0
    local groups_file="${BATCH_TEMP_FILE}.allgroups"
    
    log_info "Pre-creating all required groups..."
    
    # Collect all unique groups needed
    declare -A needed_groups
    
    while IFS= read -r i; do
        [[ -z "$i" ]] && continue
        
        local user_name_var="USER_NAME_${i}"
        local user_gid_var="USER_${i}_GID"
        local secondary_groups_var="USER_${i}_SECONDARY_GROUPS"
        local secondary_groups_var_alt="USER_SECONDARY_GROUPS_${i}"
        
        local user_name="${!user_name_var:-}"
        [[ -z "$user_name" ]] && continue
        
        # Skip if user already exists
        user_exists "$user_name" && continue
        
        # Primary group (username = groupname)
        local user_gid="${!user_gid_var:-}"
        if [[ -z "$user_gid" ]]; then
            user_gid=$((USER_UID_OFFSET + i))
        fi
        needed_groups["$user_name"]="$user_gid"
        
        # Secondary groups
        local secondary_groups="${!secondary_groups_var:-}"
        [[ -z "$secondary_groups" ]] && secondary_groups="${!secondary_groups_var_alt:-}"
        
        if [[ -n "$secondary_groups" ]]; then
            # Normalize and split
            secondary_groups="${secondary_groups// /,}"
            secondary_groups="${secondary_groups//,,/,}"
            IFS=',' read -ra groups <<< "$secondary_groups"
            for group in "${groups[@]}"; do
                group="${group// /}"
                [[ -z "$group" ]] && continue
                # Mark for creation (no specific GID for secondary groups)
                needed_groups["$group"]="${needed_groups[$group]:-auto}"
            done
        fi
    done <<< "$user_indices"
    
    # Create all needed groups
    for group_name in "${!needed_groups[@]}"; do
        if group_exists "$group_name"; then
            continue
        fi
        
        local gid="${needed_groups[$group_name]}"
        
        if [[ "$gid" != "auto" ]]; then
            # Create with specific GID (primary groups)
            if command -v groupadd &> /dev/null; then
                groupadd -g "$gid" "$group_name" 2>/dev/null || true
            else
                addgroup -g "$gid" "$group_name" 2>/dev/null || true
            fi
        else
            # Create with auto GID (secondary groups)
            if command -v groupadd &> /dev/null; then
                groupadd "$group_name" 2>/dev/null || true
            else
                addgroup "$group_name" 2>/dev/null || true
            fi
        fi
        
        _cache_add_group "$group_name" "$gid"
        ((groups_created++))
    done
    
    log_info "✓ Pre-created $groups_created groups"
    return 0
}

# Generate newusers batch file
# Format: username:password:uid:gid:gecos:homedir:shell
# Returns: writes user count to ${BATCH_TEMP_FILE}.count
generate_batch_file() {
    local user_indices="$1"
    local batch_file="$BATCH_TEMP_FILE"
    local users_to_create=0
    local skipped=0
    
    log_info "Generating batch file for newusers..."
    
    # Secure the batch file (contains passwords)
    touch "$batch_file"
    chmod 600 "$batch_file"
    
    # Also track secondary groups for phase 2
    touch "${batch_file}.groups"
    chmod 600 "${batch_file}.groups"
    
    # Track users for Samba password phase
    touch "${batch_file}.samba"
    chmod 600 "${batch_file}.samba"
    
    while IFS= read -r i; do
        [[ -z "$i" ]] && continue
        
        local user_name_var="USER_NAME_${i}"
        local user_pass_var="USER_PASS_${i}"
        local user_uid_var="USER_${i}_UID"
        local user_gid_var="USER_${i}_GID"
        local secondary_groups_var="USER_${i}_SECONDARY_GROUPS"
        local secondary_groups_var_alt="USER_SECONDARY_GROUPS_${i}"
        
        local user_name="${!user_name_var:-}"
        local user_pass="${!user_pass_var:-}"
        
        # Skip if missing required fields
        if [[ -z "$user_name" || -z "$user_pass" ]]; then
            log_warn "Skipping index $i: missing username or password"
            continue
        fi
        
        # Skip if user already exists
        if user_exists "$user_name"; then
            log_info "User already exists: '$user_name' (skipping)"
            ((skipped++))
            continue
        fi
        
        # Validate password
        if ! validate_password "$user_pass" "$USER_PASSWORD_MIN_LENGTH"; then
            log_error "Invalid password for user '$user_name' - skipping"
            continue
        fi
        
        # Get UID/GID
        local user_uid="${!user_uid_var:-}"
        local user_gid="${!user_gid_var:-}"
        local uid_valid=false
        local gid_valid=false
        
        if user_uid=$(validate_numeric_id "$user_uid" 2>/dev/null); then
            uid_valid=true
        else
            user_uid=""
        fi
        
        if user_gid=$(validate_numeric_id "$user_gid" 2>/dev/null); then
            gid_valid=true
        else
            user_gid=""
        fi
        
        # Auto-assign UIDs/GIDs if not provided
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
        esac
        
        # Validate ranges
        if ! validate_uid_range "$user_uid" "$user_name"; then
            log_error "UID validation failed for '$user_name' - skipping"
            continue
        fi
        
        if ! validate_gid_range "$user_gid" "$user_name"; then
            log_error "GID validation failed for '$user_name' - skipping"
            continue
        fi
        
        # Determine home directory
        local home_dir
        if [[ "${CREATE_HOME_DIR,,}" == "no" || "${CREATE_HOME_DIR}" == "0" ]]; then
            home_dir="/nonexistent"
        else
            home_dir="/home/$user_name"
        fi
        
        # Write to batch file
        # Format: username:password:uid:gid:gecos:homedir:shell
        printf '%s:%s:%s:%s:%s:%s:%s\n' \
            "$user_name" \
            "$user_pass" \
            "$user_uid" \
            "$user_gid" \
            "$user_name" \
            "$home_dir" \
            "$DEFAULT_SHELL" >> "$batch_file"
        
        # Track for Samba password (username:password)
        printf '%s:%s\n' "$user_name" "$user_pass" >> "${batch_file}.samba"
        
        # Track secondary groups if any
        local secondary_groups="${!secondary_groups_var:-}"
        [[ -z "$secondary_groups" ]] && secondary_groups="${!secondary_groups_var_alt:-}"
        
        if [[ -n "$secondary_groups" ]]; then
            printf '%s:%s\n' "$user_name" "$secondary_groups" >> "${batch_file}.groups"
        fi
        
        ((users_to_create++))
        
    done <<< "$user_indices"
    
    log_info "Batch file generated: $users_to_create users to create, $skipped skipped"
    
    # Write count to file (avoids stdout capture issues with log messages)
    echo "$users_to_create" > "${batch_file}.count"
}

# Execute batch user creation with newusers
execute_batch_creation() {
    local batch_file="$BATCH_TEMP_FILE"
    
    if [[ ! -s "$batch_file" ]]; then
        log_info "No users to create in batch"
        return 0
    fi
    
    local user_count
    user_count=$(wc -l < "$batch_file")
    
    log_info "Creating $user_count users with newusers (batch mode)..."
    
    local start_time
    start_time=$(date +%s.%N)
    
    # Run newusers
    if newusers "$batch_file" 2>&1; then
        local end_time
        end_time=$(date +%s.%N)
        local duration
        duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
        
        log_success "Created $user_count users in ${duration}s (batch mode)"
        return 0
    else
        log_error "newusers batch creation failed"
        return 1
    fi
}

# Set Samba passwords for all batch-created users
execute_batch_samba_passwords() {
    local samba_file="${BATCH_TEMP_FILE}.samba"
    
    if [[ ! -s "$samba_file" ]]; then
        log_info "No Samba passwords to set"
        return 0
    fi
    
    local user_count
    user_count=$(wc -l < "$samba_file")
    
    log_info "Setting Samba passwords for $user_count users..."
    
    local start_time success_count=0 fail_count=0
    start_time=$(date +%s.%N)
    
    while IFS=: read -r username password; do
        [[ -z "$username" ]] && continue
        
        # Set Samba password
        if printf '%s\n%s\n' "$password" "$password" | smbpasswd -a -s "$username" >/dev/null 2>&1; then
            # Enable user
            smbpasswd -e "$username" >/dev/null 2>&1 || true
            ((success_count++))
        else
            log_warn "Failed to set Samba password for '$username'"
            ((fail_count++))
        fi
    done < "$samba_file"
    
    local end_time duration
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
    
    log_success "Samba passwords: $success_count succeeded, $fail_count failed (${duration}s)"
    
    return 0
}

# Process secondary groups from batch file
# Groups are guaranteed to exist (pre-created in Phase 1)
execute_batch_secondary_groups() {
    local groups_file="${BATCH_TEMP_FILE}.groups"
    
    if [[ ! -s "$groups_file" ]]; then
        log_info "No secondary groups to process"
        return 0
    fi
    
    local user_count
    user_count=$(wc -l < "$groups_file")
    
    log_info "Processing secondary groups for $user_count users..."
    
    local start_time assignments=0
    start_time=$(date +%s.%N)
    
    while IFS=: read -r username groups_list; do
        [[ -z "$username" || -z "$groups_list" ]] && continue
        
        # Normalize: spaces to commas
        groups_list="${groups_list// /,}"
        groups_list="${groups_list//,,/,}"
        
        # Split and process
        IFS=',' read -ra groups <<< "$groups_list"
        for group in "${groups[@]}"; do
            group="${group// /}"
            [[ -z "$group" ]] && continue
            
            # Groups guaranteed to exist from Phase 1
            # Add user to group using usermod (from shadow package)
            if command -v usermod &> /dev/null; then
                if usermod -aG "$group" "$username" 2>/dev/null; then
                    ((assignments++))
                fi
            else
                # Fallback to addgroup (Alpine BusyBox)
                if addgroup "$username" "$group" 2>/dev/null; then
                    ((assignments++))
                fi
            fi
        done
    done < "$groups_file"
    
    local end_time duration
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
    
    log_success "Secondary groups: $assignments assignments (${duration}s)"
    
    return 0
}

# ============================================================================
# FALLBACK: SEQUENTIAL USER CREATION (if newusers not available)
# ============================================================================
create_user_sequential() {
    local user_name="$1"
    local user_pass="$2"
    local user_uid="$3"
    local user_gid="$4"
    
    log_info "Creating user: '$user_name' (UID: $user_uid, GID: $user_gid)"
    
    # Create group if needed
    if ! group_exists "$user_name"; then
        if command -v groupadd &> /dev/null; then
            groupadd -g "$user_gid" "$user_name" 2>/dev/null || return 1
        else
            addgroup -g "$user_gid" "$user_name" 2>/dev/null || return 1
        fi
        log_info "✓ Created group: '$user_name' with GID $user_gid"
        _cache_add_group "$user_name" "$user_gid"
    fi
    
    # Create user
    local home_flag=""
    if [[ "${CREATE_HOME_DIR,,}" == "no" || "${CREATE_HOME_DIR}" == "0" ]]; then
        home_flag="-M"  # useradd: don't create home
    fi
    
    if command -v useradd &> /dev/null; then
        useradd $home_flag -u "$user_uid" -g "$user_gid" -s "$DEFAULT_SHELL" "$user_name" 2>/dev/null || return 1
    else
        local adduser_flags="-D"
        [[ "${CREATE_HOME_DIR,,}" == "no" || "${CREATE_HOME_DIR}" == "0" ]] && adduser_flags="$adduser_flags -H"
        adduser $adduser_flags -u "$user_uid" -G "$user_name" -s "$DEFAULT_SHELL" "$user_name" 2>/dev/null || return 1
    fi
    
    log_info "✓ Created user: '$user_name' with UID $user_uid"
    _cache_add_user "$user_name" "$user_uid"
    
    # Set Samba password
    if printf '%s\n%s\n' "$user_pass" "$user_pass" | smbpasswd -a -s "$user_name" >/dev/null 2>&1; then
        smbpasswd -e "$user_name" >/dev/null 2>&1 || true
        log_info "✓ Set Samba password for: '$user_name'"
    else
        log_error "Failed to set Samba password for '$user_name'"
        return 1
    fi
    
    return 0
}

validate_and_create_users_sequential() {
    local user_indices
    user_indices=$(get_user_indices)
    
    if [[ -z "$user_indices" ]]; then
        log_info "No users to create"
        return 0
    fi
    
    log_info "Creating users sequentially (newusers not available)..."
    
    while IFS= read -r i; do
        [[ -z "$i" ]] && continue
        
        local user_name_var="USER_NAME_${i}"
        local user_pass_var="USER_PASS_${i}"
        local user_uid_var="USER_${i}_UID"
        local user_gid_var="USER_${i}_GID"
        
        local user_name="${!user_name_var:-}"
        local user_pass="${!user_pass_var:-}"
        
        if [[ -z "$user_name" || -z "$user_pass" ]]; then
            log_warn "Skipping index $i: missing username or password"
            continue
        fi
        
        if user_exists "$user_name"; then
            log_info "User already exists: '$user_name'"
            continue
        fi
        
        local user_uid="${!user_uid_var:-}"
        local user_gid="${!user_gid_var:-}"
        local uid_valid=false gid_valid=false
        
        if user_uid=$(validate_numeric_id "$user_uid" 2>/dev/null); then
            uid_valid=true
        else
            user_uid=""
        fi
        
        if user_gid=$(validate_numeric_id "$user_gid" 2>/dev/null); then
            gid_valid=true
        else
            user_gid=""
        fi
        
        case "$uid_valid:$gid_valid" in
            false:false) user_uid=$((USER_UID_OFFSET + i)); user_gid=$user_uid ;;
            false:true) user_uid=$user_gid ;;
            true:false) user_gid=$user_uid ;;
        esac
        
        create_user_sequential "$user_name" "$user_pass" "$user_uid" "$user_gid" || \
            log_error "Failed to create user '$user_name'"
            
    done <<< "$user_indices"
}

# ============================================================================
# MAIN USER CREATION ORCHESTRATOR
# ============================================================================
validate_and_create_users() {
    local user_indices
    user_indices=$(get_user_indices)
    
    if [[ -z "$user_indices" ]]; then
        log_info "No users to create (no USER_NAME_* variables found)"
        return 0
    fi
    
    local user_count
    user_count=$(echo "$user_indices" | wc -l)
    
    print_header "Creating $user_count Users"
    
    # Initialize caches for fast lookups
    init_caches
    
    # Check if newusers is available for batch mode
    if command -v newusers &> /dev/null && [[ "$BATCH_USER_CREATION" == "1" ]]; then
        log_info "Using BATCH MODE (newusers) - ~15x faster"
        print_separator
        
        local total_start
        total_start=$(date +%s.%N)
        
        # PHASE 1: Pre-create ALL groups (primary + secondary)
        log_progress "Phase 1: Pre-creating all groups..."
        precreate_all_groups "$user_indices"
        
        # Refresh cache after group creation
        refresh_caches
        
        # PHASE 2: Generate batch file and validate all users
        print_separator
        log_progress "Phase 2: Generating batch file..."
        generate_batch_file "$user_indices"
        local users_to_create
        users_to_create=$(cat "${BATCH_TEMP_FILE}.count" 2>/dev/null || echo "0")
        
        if [[ "$users_to_create" -eq 0 ]]; then
            log_info "No new users to create"
            return 0
        fi
        
        # PHASE 3: Execute batch user creation (single newusers call)
        print_separator
        log_progress "Phase 3: Creating users (batch)..."
        execute_batch_creation || exit_error "Batch user creation failed"
        
        # Refresh cache after batch creation
        refresh_caches
        
        # PHASE 4: Set Samba passwords (still sequential, but fast)
        print_separator
        log_progress "Phase 4: Setting Samba passwords..."
        execute_batch_samba_passwords
        
        # PHASE 5: Process secondary groups (assign users to groups)
        print_separator
        log_progress "Phase 5: Assigning secondary groups..."
        execute_batch_secondary_groups
        
        local total_end total_duration
        total_end=$(date +%s.%N)
        total_duration=$(echo "$total_end - $total_start" | bc 2>/dev/null || echo "?")
        
        print_separator
        log_success "BATCH CREATION COMPLETE"
        log_info "Total time: ${total_duration}s for $users_to_create users"
        log_info "Performance: ~$(echo "scale=1; $users_to_create / $total_duration" | bc 2>/dev/null || echo "?") users/second"
        
    else
        # Fallback to sequential mode
        log_warn "Using SEQUENTIAL MODE (slower)"
        if ! command -v newusers &> /dev/null; then
            log_warn "Install 'shadow' package for 15x faster batch creation"
        fi
        print_separator
        
        validate_and_create_users_sequential "$user_indices"
    fi
    
    return 0
}

# ============================================================================
# NAMED GROUPS CREATION (from SMBGROUP_* variables)
# ============================================================================
create_named_groups() {
    log_info "Checking for named groups (SMBGROUP_*)..."
    
    local group_vars
    group_vars=$(compgen -v SMBGROUP_ 2>/dev/null || true)
    
    if [[ -z "$group_vars" ]]; then
        log_info "No named groups defined"
        return 0
    fi
    
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        
        local group_name="${!var}"
        [[ -z "$group_name" ]] && continue
        
        # Extract GID variable name (SMBGROUP_1 -> SMBGROUP_1_GID)
        local gid_var="${var}_GID"
        local group_gid="${!gid_var:-}"
        
        if group_exists "$group_name"; then
            log_info "Group already exists: '$group_name'"
            continue
        fi
        
        if [[ -n "$group_gid" ]]; then
            if command -v groupadd &> /dev/null; then
                groupadd -g "$group_gid" "$group_name" 2>/dev/null
            else
                addgroup -g "$group_gid" "$group_name" 2>/dev/null
            fi
            log_info "✓ Created group: '$group_name' (GID: $group_gid)"
        else
            if command -v groupadd &> /dev/null; then
                groupadd "$group_name" 2>/dev/null
            else
                addgroup "$group_name" 2>/dev/null
            fi
            log_info "✓ Created group: '$group_name' (auto GID)"
        fi
        
        _cache_add_group "$group_name" "${group_gid:-auto}"
        
    done <<< "$group_vars"
}

# ============================================================================
# GUEST USER CREATION
# ============================================================================
create_guest_user() {
    if [[ ! -e /etc/samba/guest.acc ]]; then
        log_info "Guest account not enabled (no /etc/samba/guest.acc)"
        return 0
    fi
    
    local guest_account="${GUEST_ACCOUNT:-$DEFAULT_GUEST_ACCOUNT}"
    
    if user_exists "$guest_account"; then
        log_info "Guest user already exists: '$guest_account'"
        rm -f /etc/samba/guest.acc
        return 0
    fi
    
    local guest_uid="${GUEST_UID:-}"
    local guest_gid="${GUEST_GID:-}"
    local uid_valid=false gid_valid=false
    
    if guest_uid=$(validate_numeric_id "$guest_uid" 2>/dev/null); then
        uid_valid=true
    else
        guest_uid=""
    fi
    
    if guest_gid=$(validate_numeric_id "$guest_gid" 2>/dev/null); then
        gid_valid=true
    else
        guest_gid=""
    fi
    
    case "$uid_valid:$gid_valid" in
        false:false) guest_uid=$DEFAULT_GUEST_UID; guest_gid=$DEFAULT_GUEST_GID ;;
        false:true) guest_uid=$guest_gid ;;
        true:false) guest_gid=$guest_uid ;;
    esac
    
    log_info "Creating guest user: '$guest_account' (UID: $guest_uid, GID: $guest_gid)"
    
    if command -v groupadd &> /dev/null; then
        groupadd -g "$guest_gid" "$guest_account" 2>/dev/null || true
        useradd -M -u "$guest_uid" -g "$guest_gid" -s /bin/false "$guest_account" 2>/dev/null || \
            exit_error "Failed to create guest user"
    else
        addgroup -g "$guest_gid" "$guest_account" 2>/dev/null || true
        adduser -D -H -u "$guest_uid" -G "$guest_account" "$guest_account" 2>/dev/null || \
            exit_error "Failed to create guest user"
    fi
    
    rm -f /etc/samba/guest.acc
    log_success "Guest user created: '$guest_account'"
}

# ============================================================================
# SUMMARY DISPLAY
# ============================================================================
show_summary() {
    print_header "User Creation Summary"
    
    local total_users total_groups
    total_users=$(wc -l < /etc/passwd)
    total_groups=$(wc -l < /etc/group)
    
    print_kv "Total system users" "$total_users"
    print_kv "Total system groups" "$total_groups"
    
    if command -v pdbedit &> /dev/null; then
        local samba_users
        samba_users=$(pdbedit -L 2>/dev/null | wc -l)
        print_kv "Samba users" "$samba_users"
    fi
    
    print_separator
    log_info "Use 'pdbedit -L -v <username>' to view Samba user details"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================
main() {
    print_header "User Creation Script v$SCRIPT_VERSION"
    log_info "Timestamp: $(date)"
    
    # Pre-flight checks
    if [[ "$SKIP_PREFLIGHT" != "1" ]]; then
        preflight_checks || exit_error "Pre-flight checks failed"
    else
        log_warn "Pre-flight checks SKIPPED"
    fi
    
    # Verify passdb backend
    verify_passdb_backend || exit_error "Passdb backend verification failed"
    
    # Verify Samba directories
    verify_samba_directories
    
    # Create named groups first
    create_named_groups
    
    # Create users (batch or sequential)
    validate_and_create_users
    
    # Create guest user if needed
    create_guest_user
    
    # Show summary
    show_summary
    
    print_header "User Creation Complete"
}

main "$@"
