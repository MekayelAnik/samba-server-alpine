#!/bin/bash
# smbd.sh - Samba Server Entrypoint (v3.5.1)
# Optimized for production with Android/Windows/macOS compatibility
set -uo pipefail
# Note: NOT using set -e (errexit) as it causes issues with the monitoring loop

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly SMBD_SCRIPT_VERSION="3.5.2"
readonly DEBUG_MODE="${DEBUG_MODE:-0}"
readonly SMB_STATUS_UPDATE_INTERVAL="${SMB_STATUS_UPDATE_INTERVAL:-30}"
readonly BANNER_FILE="${BANNER_FILE:-/usr/bin/banner.sh}"
readonly DATA_DIR="${DATA_DIR:-/data}"

# Print version immediately
echo "[i] === Samba Entrypoint v${SMBD_SCRIPT_VERSION} ==="

# Script execution order - Users MUST be created BEFORE config validation
readonly __SCRIPT_SOURCES=("constructUsers.sh" "constructConf.sh")

# State tracking
__BANNER_EXECUTED=0

# ============================================================================
# COLORS (minimal set for production)
# ============================================================================
readonly RED='\033[38;5;9m'
readonly GREEN='\033[38;5;10m'
readonly YELLOW='\033[38;5;11m'
readonly CYAN='\033[38;5;14m'
readonly GRAY='\033[38;5;250m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# ============================================================================
# LOGGING
# ============================================================================
log_error() { printf "${BOLD}${RED}[✗]${NC} %s\n" "$*" >&2; }
log_warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*" >&2; }
log_info()  { printf "${CYAN}[i]${NC} %s\n" "$*"; }
log_ok()    { printf "${GREEN}[✓]${NC} %s\n" "$*"; }

error_exit() {
    log_error "$*"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
is_debug_enabled() {
    case "${DEBUG_MODE,,}" in
        yes|y|true|t|1) return 0 ;;
        *) return 1 ;;
    esac
}

run_banner() {
    [[ "$__BANNER_EXECUTED" -eq 1 ]] && return 0
    [[ -f "$BANNER_FILE" ]] && bash "$BANNER_FILE" 2>/dev/null
    __BANNER_EXECUTED=1
}

source_scripts() {
    printf "${GRAY}Loading configuration scripts...${NC}\n"
    
    for script in "${__SCRIPT_SOURCES[@]}"; do
        local script_path="/usr/bin/${script}"
        
        [[ ! -f "$script_path" ]] && error_exit "Script not found: $script_path"
        
        if ! source "$script_path"; then
            error_exit "Failed to source $script_path"
        fi
        
        log_ok "Loaded: $script"
    done
}

# ============================================================================
# RECYCLE BIN MAINTENANCE
# Recreates user recycle directories if deleted during operation
# ============================================================================
check_recycle_bins() {
    [[ -z "${DATA_DIR:-}" ]] && return 0
    
    local share_vars fixed=0
    share_vars=$(compgen -v | grep -E '^SHARE_NAME_[0-9]+$' 2>/dev/null) || return 0
    
    for share_name_var in $share_vars; do
        local share_name="${!share_name_var}"
        [[ -z "$share_name" ]] && continue
        
        local share_num="${share_name_var#SHARE_NAME_}"
        local recycle_var="SHARE_${share_num}_RECYCLE_BIN"
        local recycle="${!recycle_var:-no}"
        
        [[ ! "${recycle,,}" =~ ^(yes|y|true|t|1|enabled?)$ ]] && continue
        
        local share_path="${DATA_DIR}/${share_name}"
        local recycle_base="${share_path}/.recycle"
        
        # Recreate base if missing
        if [[ ! -d "$recycle_base" ]]; then
            mkdir -p "$recycle_base" 2>/dev/null || continue
            local mode_var="SHARE_${share_num}_RECYCLE_DIRECTORY_MODE"
            chmod "${!mode_var:-0777}" "$recycle_base" 2>/dev/null
            log_info "Recreated: ${recycle_base}"
            ((fixed++)) || true
        fi
        
        # Collect users from share config
        local -a raw_entries=()
        for list_var in "SHARE_${share_num}_VALID_USERS" "SHARE_${share_num}_WRITE_LIST" "SHARE_${share_num}_READ_LIST"; do
            [[ -n "${!list_var:-}" ]] && IFS=' ' read -ra tmp <<< "${!list_var}" && raw_entries+=("${tmp[@]}")
        done
        
        # Skip if no entries defined
        [[ ${#raw_entries[@]} -eq 0 ]] && continue
        
        # Expand @groups to get all users
        local -a all_users=()
        for entry in "${raw_entries[@]}"; do
            if [[ "$entry" =~ ^@(.+)$ ]]; then
                # It's a group - expand to members
                local group_name="${BASH_REMATCH[1]}"
                local group_entry
                group_entry=$(getent group "$group_name" 2>/dev/null) || continue
                local members="${group_entry##*:}"
                if [[ -n "$members" ]]; then
                    IFS=',' read -ra group_members <<< "$members"
                    all_users+=("${group_members[@]}")
                fi
            else
                # It's a user
                all_users+=("$entry")
            fi
        done
        
        # Skip if no users after expansion
        [[ ${#all_users[@]} -eq 0 ]] && continue
        
        # Create directories for unique valid users
        local subdir_mode_var="SHARE_${share_num}_RECYCLE_SUB_DIRECTORY_MODE"
        local subdir_mode="${!subdir_mode_var:-0700}"
        local processed=""
        
        for user in "${all_users[@]}"; do
            # Skip empty, duplicates, and invalid usernames
            [[ -z "$user" ]] && continue
            [[ " $processed " =~ " $user " ]] && continue
            [[ ! "$user" =~ ^[a-zA-Z0-9._-]+$ ]] && continue
            processed="$processed $user"
            
            # Create user directory if user exists and directory missing
            if id "$user" >/dev/null 2>&1 && [[ ! -d "$recycle_base/$user" ]]; then
                mkdir -p "$recycle_base/$user" 2>/dev/null || continue
                chown "$user:$user" "$recycle_base/$user" 2>/dev/null || true
                chmod "$subdir_mode" "$recycle_base/$user" 2>/dev/null || true
                log_info "Recreated recycle dir for: $user"
                ((fixed++)) || true
            fi
        done
    done
    
    [[ $fixed -gt 0 ]] && log_ok "Fixed $fixed recycle directories"
    return 0
}

# ============================================================================
# SERVER LIFECYCLE
# ============================================================================
start_server() {
    # Run banner first (before anything else)
    run_banner
    
    # Validate interval
    [[ ! "$SMB_STATUS_UPDATE_INTERVAL" =~ ^[0-9]+$ ]] && \
        error_exit "SMB_STATUS_UPDATE_INTERVAL must be numeric"
    
    # Deprecation warnings
    [[ -n "${NUMBER_OF_SHARES:-}" ]] && \
        log_warn "NUMBER_OF_SHARES is deprecated (shares auto-discovered via SHARE_NAME_*)"
    [[ -n "${NUMBER_OF_USERS:-}" ]] && \
        log_warn "NUMBER_OF_USERS is deprecated (users auto-discovered via USER_NAME_*)"
    
    source_scripts
    
    # === ENTERPRISE-SCALE RESOURCE LIMITS (50K+ connections) ===
    log_info "Setting enterprise-scale resource limits..."
    
    # Apply kernel tuning if sysctl available and we have permissions
    if [[ -f /etc/sysctl.d/99-samba-sysctl.conf ]]; then
        sysctl -p /etc/sysctl.d/99-samba-sysctl.conf 2>/dev/null && \
            log_ok "Applied kernel tuning from /etc/sysctl.d/99-samba-sysctl.conf" || \
            log_warn "Could not apply sysctl (need --privileged)"
    elif [[ -f /etc/sysctl.conf ]]; then
        sysctl -p /etc/sysctl.conf 2>/dev/null && \
            log_ok "Applied kernel tuning from /etc/sysctl.conf" || \
            log_warn "Could not apply sysctl (need --privileged)"
    fi
    
    # File descriptors: need ~2 per connection + overhead
    # 50 connections × 1000 clients = 50,000 connections × 2 = 100,000+ FDs
    ulimit -n 1048576 2>/dev/null || ulimit -n 524288 2>/dev/null || \
        ulimit -n 262144 2>/dev/null || ulimit -n 131072 2>/dev/null || \
        log_warn "Could not set high file descriptor limit (need Docker ulimits)"
    
    # Max processes
    ulimit -u 65535 2>/dev/null || log_warn "Could not set process limit"
    
    # Core dumps (disable for production)
    ulimit -c 0 2>/dev/null || true
    
    # Stack size
    ulimit -s unlimited 2>/dev/null || true
    
    log_ok "Resource limits: nofile=$(ulimit -n), nproc=$(ulimit -u)"
    
    printf "${GREEN}Starting Samba...${NC}\n"
    smbd || error_exit "Failed to start smbd"
    log_ok "Samba started successfully"
    
    # Simple status monitoring loop - no background processes needed
    while true; do
        smbstatus 2>/dev/null || true
        check_recycle_bins || true
        sleep "$SMB_STATUS_UPDATE_INTERVAL" || true
    done
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    if is_debug_enabled; then
        if [[ -n "${CUSTOM_ENTRYPOINT:-}" && -x "${CUSTOM_ENTRYPOINT}" ]]; then
            log_warn "Debug mode: Running custom entrypoint"
            "$CUSTOM_ENTRYPOINT"
        else
            apk add nano 2>/dev/null || true
            exec sleep infinity
        fi
    else
        run_banner
        start_server
    fi
}

main "$@"
