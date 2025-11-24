#!/bin/bash
# constructUsers.sh - Enhanced with all 9 missing features
# Features: Pre-flight checks, password validation, secondary groups, Samba verification,
#           user verification, error recovery, passdb backend checks
set -euo pipefail

# Script metadata (conditional to avoid conflicts when sourced)
if [[ -z "${CONSTRUCT_USER_SCRIPT_NAME:-}" ]]; then
    readonly CONSTRUCT_USER_SCRIPT_NAME="$(basename "$0")"
fi
if [[ -z "${CONSTRUCT_USER_SCRIPT_VERSION:-}" ]]; then
    # CONSTRUCT_USER_SCRIPT_VERSION format YYYY.MM.DD
    readonly CONSTRUCT_USER_SCRIPT_VERSION="2025.11.24"
fi

# === 2025 Best Practice Defaults (Research-Backed) ===

# Guest Account (LSB/nobody standard - changed from 9999)
# Research: Linux Standard Base specifies 65534 for nobody/nogroup
readonly DEFAULT_GUEST_ACCOUNT='guest'
readonly DEFAULT_GUEST_UID="${GUEST_UID:-65534}"
readonly DEFAULT_GUEST_GID="${GUEST_GID:-65534}"

# UID/GID Ranges (systemd/RHEL 2025 standard)
# Research: systemd standard is 1000-60000 for regular users
readonly DEFAULT_UID_MIN="${UID_MIN:-1000}"
readonly DEFAULT_UID_MAX="${UID_MAX:-60000}"
readonly DEFAULT_GID_MIN="${GID_MIN:-1000}"
readonly DEFAULT_GID_MAX="${GID_MAX:-60000}"

# User Creation Starting Point (best practice offset)
# Research: Start at 1100 to leave room for manual assignments 1000-1099
readonly USER_UID_OFFSET="${USER_UID_OFFSET:-1100}"

# Home Directory Policy (Samba-optimized)
# Research: Samba users don't need home directories (security best practice)
readonly CREATE_HOME_DIR="${CREATE_HOME_DIR:-no}"
readonly HOME_DIR_PERMISSIONS="${HOME_DIR_PERMISSIONS:-700}"

# Default Shell (Samba security best practice)
# Research: /bin/false prevents shell access for Samba-only users
readonly DEFAULT_SHELL="${DEFAULT_SHELL:-/bin/false}"

# umask Security (ANSSI 2025 recommendation)
# Research: ANSSI recommends umask 027 for secure Linux systems
readonly DEFAULT_UMASK="${DEFAULT_UMASK:-027}"

# Validation Strictness
readonly ENFORCE_OPTIMAL_VALUES="${ENFORCE_OPTIMAL_VALUES:-0}"  # Set to 1 to block non-optimal values

# Configuration from environment
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
    readonly PURPLE='\033[38;5;141m'
    readonly MAGENTA='\033[38;5;13m'
fi

# === Neutral Colors ===
if [[ -z "${ASH_GRAY:-}" ]]; then
    readonly ASH_GRAY='\033[38;5;250m'
    readonly DARK_GRAY='\033[38;5;240m'
    readonly LIGHT_GRAY='\033[38;5;252m'
    readonly WHITE='\033[38;5;15m'
fi

# === Special Colors ===
if [[ -z "${GOLD:-}" ]]; then
    readonly GOLD='\033[38;5;220m'
    readonly TEAL='\033[38;5;45m'
    readonly PINK='\033[38;5;213m'
    readonly AMBER='\033[38;5;214m'
fi

# === Reset ===
if [[ -z "${NC:-}" ]]; then
    readonly NC='\033[0m'
    readonly BOLD='\033[1m'
fi

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

print_check() {
    printf "  ${SUCCESS_GREEN}✓${NC} %s\n" "$*"
}

print_cross() {
    printf "  ${ERROR_RED}✗${NC} %s\n" "$*"
}

print_warning() {
    printf "  ${WARNING_YELLOW}!${NC} %s\n" "$*"
}

print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${BOLD}${WHITE}%-20s${NC} ${TEAL}%s${NC}\n" "$key:" "$value"
}

# === 2025 Best Practice Validation Functions ===

validate_uid_range() {
    local uid="$1"
    local username="$2"
    local warnings=()
    local risks=()
    
    # Critical: UID 0 is root
    if [[ "$uid" -eq 0 ]]; then
        printf "\n${BOLD}${ERROR_RED}┌──────────────────────────────────────────────────────────────────┐${NC}\n"
        printf "${BOLD}${ERROR_RED}│ !! CRITICAL SECURITY RISK: UID 0 IS ROOT                        │${NC}\n"
        printf "${BOLD}${ERROR_RED}├──────────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${ERROR_RED}│${NC}   User: ${WHITE}%-56s${NC} ${ERROR_RED}│${NC}\n" "$username"
        printf "${ERROR_RED}│${NC}   ${BOLD}Risk:${NC} This user will have FULL ROOT PRIVILEGES              ${ERROR_RED}│${NC}\n"
        printf "${ERROR_RED}│${NC}   ${BOLD}Impact:${NC} Complete system compromise possible                  ${ERROR_RED}│${NC}\n"
        printf "${BOLD}${ERROR_RED}└──────────────────────────────────────────────────────────────────┘${NC}\n\n"
        return 1
    fi
    
    # Critical: System UID range (1-999)
    if [[ "$uid" -ge 1 && "$uid" -lt "$DEFAULT_UID_MIN" ]]; then
        warnings+=("UID $uid is in SYSTEM RANGE (1-999)")
        risks+=("- May conflict with system services and daemons")
        risks+=("- Not portable across systems (system UIDs vary)")
        risks+=("- Could break system services if UID already in use")
        risks+=("- Violates systemd/RHEL 2025 standards")
        printf "\n${WARNING_YELLOW}========================================================${NC}\n"
        log_warn "!  NON-OPTIMAL UID DETECTED"
        log_warn "    User: $username"
        log_warn "    UID: $uid (SYSTEM RANGE)"
        log_warn "    Optimal Range: $DEFAULT_UID_MIN-$DEFAULT_UID_MAX"
        log_warn ""
        log_warn "RISKS:"
        for risk in "${risks[@]}"; do
            log_warn "    $risk"
        done
        log_warn ""
        log_warn "RECOMMENDATION: Use UID >= $USER_UID_OFFSET"
        log_warn "========================================================"
        
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            return 1
        fi
    fi
    
    # Warning: Below recommended starting point
    if [[ "$uid" -ge "$DEFAULT_UID_MIN" && "$uid" -lt "$USER_UID_OFFSET" ]]; then
        log_warn "========================================================"
        log_warn "!  SUBOPTIMAL UID DETECTED"
        log_warn "    User: $username"
        log_warn "    UID: $uid"
        log_warn "    Optimal Starting Point: $USER_UID_OFFSET"
        log_warn ""
        log_warn "POTENTIAL ISSUES:"
        log_warn "    - UID range 1000-1099 reserved for manual assignments"
        log_warn "    - May conflict with manually created users"
        log_warn "    - Reduces organizational flexibility"
        log_warn ""
        log_warn "RECOMMENDATION: Use UID >= $USER_UID_OFFSET for auto-created users"
        log_warn "========================================================"
    fi
    
    # Warning: Exceeds recommended maximum
    if [[ "$uid" -gt "$DEFAULT_UID_MAX" && "$uid" -lt 65534 ]]; then
        log_warn "========================================================"
        log_warn "!  UID EXCEEDS RECOMMENDED MAXIMUM"
        log_warn "    User: $username"
        log_warn "    UID: $uid"
        log_warn "    Recommended Maximum: $DEFAULT_UID_MAX"
        log_warn ""
        log_warn "POTENTIAL ISSUES:"
        log_warn "    - May not work with all Linux utilities (adduser limits)"
        log_warn "    - Could conflict with special UID ranges (60000-65533)"
        log_warn "    - Systemd reserved ranges: 60001-65533"
        log_warn "    - Reduces portability across systems"
        log_warn ""
        log_warn "RECOMMENDATION: Use UID range $USER_UID_OFFSET-$DEFAULT_UID_MAX"
        log_warn "========================================================"
    fi
    
    # Info: Using nobody/nogroup range
    if [[ "$uid" -eq 65534 ]]; then
        log_info "i  UID 65534 is standard nobody/nogroup (acceptable for guest accounts)"
    fi
    
    # Warning: Extended range
    if [[ "$uid" -gt 65534 ]]; then
        log_warn "========================================================"
        log_warn "!  UID IN EXTENDED RANGE"
        log_warn "    User: $username"
        log_warn "    UID: $uid"
        log_warn ""
        log_warn "POTENTIAL ISSUES:"
        log_warn "    - Extended range (65535+) intended for containers/namespaces"
        log_warn "    - May not be supported by all tools"
        log_warn "    - Could cause compatibility issues"
        log_warn "    - Not recommended for regular users"
        log_warn ""
        log_warn "RECOMMENDATION: Use UID range $USER_UID_OFFSET-$DEFAULT_UID_MAX"
        log_warn "========================================================"
    fi
    
    return 0
}

validate_gid_range() {
    local gid="$1"
    local groupname="$2"
    
    # Same logic as UID validation
    if [[ "$gid" -eq 0 ]]; then
        log_error "!  CRITICAL SECURITY RISK: GID 0 is reserved for root group!"
        log_error "    Group: $groupname"
        log_error "    Risk: Members will have ROOT GROUP PRIVILEGES"
        return 1
    fi
    
    if [[ "$gid" -ge 1 && "$gid" -lt "$DEFAULT_GID_MIN" ]]; then
        log_warn "========================================================"
        log_warn "!  NON-OPTIMAL GID DETECTED"
        log_warn "    Group: $groupname"
        log_warn "    GID: $gid (SYSTEM RANGE)"
        log_warn "    Optimal Range: $DEFAULT_GID_MIN-$DEFAULT_GID_MAX"
        log_warn ""
        log_warn "RISKS:"
        log_warn "    - May conflict with system groups"
        log_warn "    - Not portable across systems"
        log_warn "    - Violates 2025 standards"
        log_warn ""
        log_warn "RECOMMENDATION: Use GID >= $DEFAULT_GID_MIN"
        log_warn "========================================================"
        
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            return 1
        fi
    fi
    
    if [[ "$gid" -gt "$DEFAULT_GID_MAX" && "$gid" -lt 65534 ]]; then
        log_warn "========================================================"
        log_warn "!  GID EXCEEDS RECOMMENDED MAXIMUM"
        log_warn "    Group: $groupname"
        log_warn "    GID: $gid"
        log_warn "    Recommended Maximum: $DEFAULT_GID_MAX"
        log_warn "========================================================"
    fi
    
    return 0
}

validate_password_strength() {
    local password="$1"
    local username="$2"
    local length="${#password}"
    
    # Check minimum length
    if [[ "$length" -lt "$USER_PASSWORD_MIN_LENGTH" ]]; then
        log_error "!  PASSWORD TOO SHORT"
        log_error "    User: $username"
        log_error "    Length: $length characters"
        log_error "    Minimum Required: $USER_PASSWORD_MIN_LENGTH characters (2025 security standard)"
        log_error ""
        log_error "SECURITY RISKS:"
        log_error "    - Vulnerable to brute force attacks"
        log_error "    - Does not meet ANSSI/NIST 2025 guidelines"
        log_error "    - Easily guessable by automated tools"
        log_error ""
        log_error "RECOMMENDATION: Use $USER_PASSWORD_MIN_LENGTH+ character passwords"
        return 1
    fi
    
    # Warnings for weak patterns (informational)
    if [[ "$length" -lt 14 ]]; then
        log_warn "========================================================"
        log_warn "i  PASSWORD LENGTH ADVISORY"
        log_warn "    User: $username"
        log_warn "    Length: $length characters (acceptable)"
        log_warn "    Optimal Length: 14+ characters"
        log_warn ""
        log_warn "ADVISORY: 2025 best practices recommend 14+ character passwords"
        log_warn "          for high-security environments"
        log_warn "========================================================"
    fi
    
    return 0
}

validate_shell_choice() {
    local shell="$1"
    local username="$2"
    
    # Check if shell is optimal for Samba
    case "$shell" in
        /bin/false|/sbin/nologin)
            # Optimal - no warnings
            return 0
            ;;
        /bin/ash|/bin/sh|/bin/bash|/bin/zsh|/bin/dash)
            log_warn "========================================================"
            log_warn "!  NON-OPTIMAL SHELL FOR SAMBA USER"
            log_warn "    User: $username"
            log_warn "    Shell: $shell"
            log_warn "    Optimal: /bin/false or /sbin/nologin"
            log_warn ""
            log_warn "SECURITY CONSIDERATIONS:"
            log_warn "    - Samba-only users don't need shell access"
            log_warn "    - Interactive shells increase attack surface"
            log_warn "    - Users could access system via SSH if enabled"
            log_warn "    - Violates principle of least privilege"
            log_warn ""
            log_warn "RECOMMENDATION: Use /bin/false for Samba-only users"
            log_warn "========================================================"
            ;;
        *)
            log_warn "!  Unknown shell: $shell (for user $username)"
            ;;
    esac
    
    return 0
}

validate_umask_value() {
    local umask_val="$1"
    
    if [[ -z "$umask_val" ]]; then
        log_warn "========================================================"
        log_warn "!  NO UMASK CONFIGURED"
        log_warn "    Current: (using system default)"
        log_warn "    Optimal: 027 (ANSSI 2025 recommendation)"
        log_warn ""
        log_warn "SECURITY IMPACT:"
        log_warn "    - Default umask (usually 022) creates world-readable files"
        log_warn "    - Files: 644 (rw-r--r--) - readable by all users"
        log_warn "    - Directories: 755 (rwxr-xr-x) - accessible by all"
        log_warn ""
        log_warn "RECOMMENDATION: Set DEFAULT_UMASK=027"
        log_warn "    - Files: 640 (rw-r-----) - owner/group only"
        log_warn "    - Directories: 750 (rwxr-x---) - owner/group only"
        log_warn "========================================================"
        return 0
    fi
    
    case "$umask_val" in
        027)
            # Optimal - no warning
            return 0
            ;;
        077)
            log_info "i  umask 077 detected: Maximum security (owner-only access)"
            return 0
            ;;
        022)
            log_warn "========================================================"
            log_warn "!  SUBOPTIMAL UMASK DETECTED"
            log_warn "    Current: 022"
            log_warn "    Optimal: 027 (ANSSI 2025 recommendation)"
            log_warn ""
            log_warn "SECURITY IMPACT:"
            log_warn "    - umask 022 creates world-readable files"
            log_warn "    - Files: 644 (rw-r--r--) - all users can read"
            log_warn "    - Directories: 755 (rwxr-xr-x) - all users can access"
            log_warn ""
            log_warn "RECOMMENDATION: Set DEFAULT_UMASK=027 for better security"
            log_warn "========================================================"
            ;;
        002)
            log_warn "========================================================"
            log_warn "!  PERMISSIVE UMASK DETECTED"
            log_warn "    Current: 002 (group collaboration mode)"
            log_warn "    Optimal: 027 (ANSSI 2025 recommendation)"
            log_warn ""
            log_warn "SECURITY IMPACT:"
            log_warn "    - umask 002 creates group-writable files"
            log_warn "    - Files: 664 (rw-rw-r--) - group can modify"
            log_warn "    - Risk of unauthorized modifications"
            log_warn ""
            log_warn "USE CASE: Only appropriate for trusted group collaboration"
            log_warn "RECOMMENDATION: Use 027 for Samba file servers"
            log_warn "========================================================"
            ;;
        *)
            log_warn "!  Non-standard umask: $umask_val"
            log_warn "    Recommended: 027 (ANSSI 2025)"
            ;;
    esac
    
    return 0
}

# === Numeric Validation (IDs only, NOT usernames) ===
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

# === FEATURE 5: Pre-flight Checks ===
preflight_checks() {
    log_info "=== Running Pre-flight Checks ==="
    local checks_passed=0
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi
    log_info "✓ Running as root"
    ((checks_passed++))
    
    # Check required commands
    local required_cmds=("adduser" "addgroup" "smbpasswd" "id" "getent")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    log_info "✓ Found all required commands (${#required_cmds[@]})"
    ((checks_passed++))
    
    # Check smb.conf exists
    if [[ ! -f "$SMB_CONF" ]]; then
        log_error "smb.conf not found: $SMB_CONF"
        return 1
    fi
    log_info "✓ Found smb.conf: $SMB_CONF"
    ((checks_passed++))
    
    # Check if smb.conf is readable
    if [[ ! -r "$SMB_CONF" ]]; then
        log_error "Cannot read smb.conf: $SMB_CONF"
        return 1
    fi
    log_info "✓ smb.conf is readable"
    ((checks_passed++))
    
    # Validate smb.conf syntax
    if command -v testparm &> /dev/null; then
        if ! testparm -s "$SMB_CONF" >/dev/null 2>&1; then
            log_error "smb.conf has syntax errors"
            return 1
        fi
        log_info "✓ smb.conf syntax is valid"
        ((checks_passed++))
    else
        log_warn "testparm not available, skipping syntax check"
    fi
    
    # Check /etc/passwd and /etc/group accessibility
    if [[ ! -r /etc/passwd ]]; then
        log_error "Cannot read /etc/passwd"
        return 1
    fi
    if [[ ! -r /etc/group ]]; then
        log_error "Cannot read /etc/group"
        return 1
    fi
    log_info "✓ System files accessible (/etc/passwd, /etc/group)"
    ((checks_passed++))
    
    log_info "✓ Pre-flight checks passed: $checks_passed checks"
    return 0
}

# === FEATURE 3: Passdb Backend Verification ===
verify_passdb_backend() {
    log_info "=== Verifying Samba Passdb Backend ==="
    
    # Check if passdb backend is configured
    if ! grep -q "passdb backend" "$SMB_CONF"; then
        log_warn "passdb backend not explicitly set in smb.conf, assuming tdbsam (default)"
        return 0
    fi
    
    # Extract passdb backend
    local passdb_backend
    passdb_backend=$(grep "^[[:space:]]*passdb backend" "$SMB_CONF" | cut -d= -f2 | xargs)
    
    # Check if it's a supported backend
    case "$passdb_backend" in
        tdbsam|ldapsam|passdb|samba_dsdb)
            log_info "✓ Valid passdb backend configured: $passdb_backend"
            return 0
            ;;
        *)
            log_warn "Unknown passdb backend: $passdb_backend (continuing anyway)"
            return 0
            ;;
    esac
}

verify_samba_directories() {
    log_info "Verifying Samba directories..."
    
    local required_dirs=(
        "$SAMBA_PRIVATE_DIR"
        "$SAMBA_STATE_DIR"
        "$SAMBA_LOCK_DIR"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_warn "Samba directory does not exist: $dir"
            if mkdir -p "$dir" 2>/dev/null; then
                log_info "✓ Created directory: $dir"
            else
                log_warn "Could not create directory: $dir (will attempt user creation anyway)"
            fi
        else
            log_info "✓ Directory exists: $dir"
        fi
    done
}

# === FEATURE 4: Password Validation ===
validate_password() {
    local password="$1"
    local min_length="${2:-$USER_PASSWORD_MIN_LENGTH}"
    local strict_mode="${3:-$USER_PASSWORD_STRICT_MODE}"
    
    # Check if empty
    if [[ -z "$password" ]]; then
        log_error "Password cannot be empty"
        return 1
    fi
    
    # Check minimum length
    if [[ ${#password} -lt $min_length ]]; then
        log_error "Password too short (minimum $min_length characters, got ${#password})"
        return 1
    fi
    
    # Strict mode: check complexity
    if [[ "$strict_mode" == "1" ]]; then
        local has_lower=0 has_upper=0 has_digit=0 has_special=0
        
        [[ "$password" =~ [a-z] ]] && has_lower=1
        [[ "$password" =~ [A-Z] ]] && has_upper=1
        [[ "$password" =~ [0-9] ]] && has_digit=1
        [[ "$password" =~ [^a-zA-Z0-9] ]] && has_special=1
        
        local complexity=$((has_lower + has_upper + has_digit + has_special))
        if [[ $complexity -lt 3 ]]; then
            log_warn "Password has low complexity for '$user_name' (consider adding uppercase, numbers, or special characters)"
        else
            log_info "✓ Password has good complexity for user"
        fi
    fi
    
    return 0
}

# === Basic Helper Functions ===
user_exists() {
    id "$1" >/dev/null 2>&1
}

group_exists() {
    getent group "$1" >/dev/null 2>&1
}

# === FEATURE 6: Samba User Enablement Verification ===
verify_samba_user() {
    local user_name="$1"
    
    # Check if pdbedit is available
    if ! command -v pdbedit &> /dev/null; then
        log_warn "pdbedit not available, skipping Samba user verification"
        return 0
    fi
    
    # Check if user exists in Samba database
    if ! pdbedit -L 2>/dev/null | grep -q "^${user_name}:"; then
        log_error "User '$user_name' not found in Samba database"
        return 1
    fi
    log_info "✓ User '$user_name' found in Samba database"
    
    # Check if user is disabled
    if pdbedit -L -v "$user_name" 2>/dev/null | grep -q "Account Flags.*D"; then
        log_error "Samba user '$user_name' is disabled"
        return 1
    fi
    log_info "✓ Samba user '$user_name' is enabled"
    
    return 0
}

# === FEATURE 7: User Creation Verification ===
verify_user_complete() {
    local user_name="$1"
    local user_uid="$2"
    local user_gid="$3"
    
    log_info "Performing complete verification for user '$user_name'..."
    
    # Check in /etc/passwd
    if ! getent passwd "$user_name" >/dev/null; then
        log_error "User not found in /etc/passwd"
        return 1
    fi
    
    # Verify UID matches
    local actual_uid
    actual_uid=$(getent passwd "$user_name" | cut -d: -f3)
    if [[ "$actual_uid" != "$user_uid" ]]; then
        log_warn "UID mismatch: expected $user_uid, got $actual_uid"
    else
        log_info "✓ UID matches: $user_uid"
    fi
    
    # Check in /etc/group
    if ! getent group "$user_name" >/dev/null; then
        log_error "Primary group not found in /etc/group"
        return 1
    fi
    
    # Verify GID matches
    local actual_gid
    actual_gid=$(getent group "$user_name" | cut -d: -f3)
    if [[ "$actual_gid" != "$user_gid" ]]; then
        log_warn "GID mismatch: expected $user_gid, got $actual_gid"
    else
        log_info "✓ GID matches: $user_gid"
    fi
    
    # Check shell is nologin
    local shell
    shell=$(getent passwd "$user_name" | cut -d: -f7)
    if [[ "$shell" != "/sbin/nologin" && "$shell" != "/usr/sbin/nologin" ]]; then
        log_warn "Shell is not nologin: $shell"
    else
        log_info "✓ Shell correctly set to nologin (no SSH access)"
    fi
    
    return 0
}

show_user_summary() {
    local user_name="$1"
    
    log_info ""
    log_info "===== User Creation Summary: $user_name ====="
    local user_info
    user_info=$(getent passwd "$user_name")
    local uid gid home shell
    uid=$(echo "$user_info" | cut -d: -f3)
    gid=$(echo "$user_info" | cut -d: -f4)
    home=$(echo "$user_info" | cut -d: -f6)
    shell=$(echo "$user_info" | cut -d: -f7)
    
    # Check if home directory actually exists
    local home_status
    if [[ -d "$home" ]]; then
        home_status="$home (exists)"
    else
        home_status="$home (not created)"
    fi
    
    printf "  User: %s\n  UID: %s\n  GID: %s\n  Home: %s\n  Shell: %s\n" \
        "$user_name" "$uid" "$gid" "$home_status" "$shell"
    
    log_info "  Groups:"
    groups "$user_name" 2>/dev/null | sed 's/^/    /' || log_warn "    Could not fetch groups"
    
    # Show Samba details if available
    if command -v pdbedit &> /dev/null; then
        log_info "  Samba Status:"
        pdbedit -L -v "$user_name" 2>/dev/null | \
            grep -E "^(Account Flags|Full Name):" | \
            sed 's/^/    /' || log_warn "    Could not fetch Samba details"
    fi
    
    log_info "===== End Summary ====="
    log_info ""
}

# === FEATURE 2: Secondary Groups Support ===
create_secondary_group() {
    local group_name="$1"
    local group_gid="${2:-}"
    
    if group_exists "$group_name"; then
        log_info "Group already exists: '$group_name'"
        return 0
    fi
    
    # Create with or without specific GID
    if [[ -n "$group_gid" ]]; then
        if addgroup -g "$group_gid" "$group_name" 2>/dev/null; then
            log_info "✓ Created secondary group: '$group_name' with GID $group_gid"
            return 0
        else
            log_error "Failed to create group '$group_name' with GID $group_gid"
            return 1
        fi
    else
        if addgroup "$group_name" 2>/dev/null; then
            log_info "✓ Created secondary group: '$group_name' (auto-assigned GID)"
            return 0
        else
            log_error "Failed to create group '$group_name'"
            return 1
        fi
    fi
}

add_user_to_group() {
    local user_name="$1"
    local group_name="$2"
    
    if ! user_exists "$user_name"; then
        log_error "User '$user_name' does not exist"
        return 1
    fi
    
    if ! group_exists "$group_name"; then
        log_error "Group '$group_name' does not exist"
        return 1
    fi
    
    # Check if user already in group
    local group_gid
    group_gid=$(getent group "$group_name" | cut -d: -f3)
    if id -G "$user_name" 2>/dev/null | grep -qw "$group_gid"; then
        log_info "User '$user_name' already in group '$group_name'"
        return 0
    fi
    
    if addgroup "$user_name" "$group_name" 2>/dev/null; then
        log_info "✓ Added user '$user_name' to group '$group_name'"
        return 0
    else
        log_error "Failed to add user '$user_name' to group '$group_name'"
        return 1
    fi
}

# === FEATURE 9: Error Recovery & Cleanup ===
cleanup_user_on_failure() {
    local user_name="$1"
    local group_name="$2"
    local force_cleanup="${3:-$FORCE_CLEANUP}"
    
    log_warn "Attempting cleanup for failed user creation: '$user_name'"
    
    # Check if running in interactive terminal
    local is_interactive=0
    if [[ -t 0 ]]; then
        is_interactive=1
    fi
    
    # Prompt before cleanup ONLY if:
    # 1. Running interactively (has TTY)
    # 2. Not forced
    # 3. Auto cleanup not enabled
    if [[ "$is_interactive" == "1" && "$force_cleanup" != "1" && "$AUTO_CLEANUP_ON_FAILURE" != "1" ]]; then
        log_warn "This will delete user '$user_name' and group '$group_name'"
        read -p "Continue with cleanup? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warn "Cleanup cancelled by user"
            return 1
        fi
    else
        # Non-interactive or forced - always cleanup
        if [[ "$is_interactive" == "0" ]]; then
            log_info "Non-interactive environment detected - auto-cleanup enabled"
        fi
    fi
    
    # Remove from Samba database
    if smbpasswd -x "$user_name" 2>/dev/null; then
        log_info "✓ Removed from Samba database"
    fi
    
    # Remove user
    if deluser "$user_name" 2>/dev/null; then
        log_info "✓ Deleted user: $user_name"
    else
        log_warn "Failed to delete user (may need manual cleanup)"
    fi
    
    # Remove group
    if delgroup "$group_name" 2>/dev/null; then
        log_info "✓ Deleted group: $group_name"
    else
        log_warn "Failed to delete group (may need manual cleanup)"
    fi
}

# === Core User Creation ===
create_user() {
    local user_name="$1"
    local user_pass="$2"
    local user_uid="$3"
    local user_gid="$4"
    
    log_info "Creating user: '$user_name' (UID: $user_uid, GID: $user_gid)"
    
    # === 2025 VALIDATION: Check for non-optimal values ===
    log_info ""
    log_info "=== Running 2025 Best Practice Validations ==="
    
    # Validate UID range
    if ! validate_uid_range "$user_uid" "$user_name"; then
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            log_error "User creation blocked: UID $user_uid violates optimal range"
            log_error "Set ENFORCE_OPTIMAL_VALUES=0 to allow creation with warnings"
            return 1
        fi
    fi
    
    # Validate GID range
    if ! validate_gid_range "$user_gid" "$user_name"; then
        if [[ "$ENFORCE_OPTIMAL_VALUES" -eq 1 ]]; then
            log_error "User creation blocked: GID $user_gid violates optimal range"
            log_error "Set ENFORCE_OPTIMAL_VALUES=0 to allow creation with warnings"
            return 1
        fi
    fi
    
    # Validate password strength
    if ! validate_password_strength "$user_pass" "$user_name"; then
        log_error "Password validation failed for user '$user_name'"
        return 1
    fi
    
    # Validate shell choice (will check after user creation)
    # Validate umask (global setting)
    validate_umask_value "$DEFAULT_UMASK"
    
    log_info "=== Validation Complete - Proceeding with user creation ==="
    log_info ""
    
    # Check if user already exists
    if getent passwd "$user_name" >/dev/null 2>&1; then
        log_warn "User '$user_name' already exists"
        log_info "Verifying existing user..."
        
        # Verify the existing user
        local existing_uid
        existing_uid=$(getent passwd "$user_name" | cut -d: -f3)
        
        if [[ "$existing_uid" == "$user_uid" ]]; then
            log_info "✓ User '$user_name' exists with correct UID $user_uid"
            
            # Still need to set Samba password
            if printf '%s\n%s\n' "$user_pass" "$user_pass" | smbpasswd -a -s "$user_name" >/dev/null 2>&1; then
                log_info "✓ Set Samba password for: '$user_name'"
            else
                log_error "Failed to set Samba password for existing user '$user_name'"
                return 1
            fi
            
            smbpasswd -e "$user_name" >/dev/null 2>&1 || true
            
            # Show summary
            print_user_summary "$user_name"
            return 0
        else
            log_error "User '$user_name' exists but with wrong UID: $existing_uid (expected: $user_uid)"
            log_error "Please remove existing user first or use a different username"
            return 1
        fi
    fi
    
    # Check if group already exists
    if getent group "$user_name" >/dev/null 2>&1; then
        local existing_gid
        existing_gid=$(getent group "$user_name" | cut -d: -f3)
        
        if [[ "$existing_gid" == "$user_gid" ]]; then
            log_info "✓ Group '$user_name' already exists with GID $user_gid"
        else
            log_error "Group '$user_name' exists but with wrong GID: $existing_gid (expected: $user_gid)"
            log_error "Please remove existing group first or use a different name"
            return 1
        fi
    else
        # Create group
        if addgroup -g "$user_gid" "$user_name" 2>/dev/null; then
            log_info "✓ Created group: '$user_name' with GID $user_gid"
        else
            log_error "Failed to create group '$user_name'"
            return 1
        fi
    fi
    
    # Determine adduser flags based on configuration
    local adduser_flags="-D"  # Always disable password (will use smbpasswd)
    
    # Home directory flag
    if [[ "${CREATE_HOME_DIR,,}" == "no" || "${CREATE_HOME_DIR}" == "0" ]]; then
        adduser_flags="$adduser_flags -H"
        log_info "Not creating home directory (CREATE_HOME_DIR=$CREATE_HOME_DIR)"
    else
        log_info "Creating home directory (CREATE_HOME_DIR=$CREATE_HOME_DIR)"
    fi
    
    # Shell flag
    local shell="${DEFAULT_SHELL:-/bin/false}"
    adduser_flags="$adduser_flags -s $shell"
    
    # Create user with optimal settings
    if adduser $adduser_flags -u "$user_uid" -G "$user_name" "$user_name" 2>&1; then
        log_info "✓ Created user: '$user_name' with UID $user_uid"
    else
        log_error "Failed to create user '$user_name'"
        log_error "adduser flags used: $adduser_flags -u $user_uid -G $user_name"
        delgroup "$user_name" 2>/dev/null
        return 1
    fi
    
    # Validate shell choice after creation
    validate_shell_choice "$shell" "$user_name"
    
    # Set home directory permissions if created
    if [[ "${CREATE_HOME_DIR,,}" != "no" && "${CREATE_HOME_DIR}" != "0" ]]; then
        local home_dir="/home/$user_name"
        if [[ -d "$home_dir" ]]; then
            local perm="${HOME_DIR_PERMISSIONS:-700}"
            if chmod "$perm" "$home_dir" 2>/dev/null; then
                log_info "✓ Set home directory permissions to $perm: $home_dir"
            else
                log_warn "Failed to set home directory permissions"
            fi
        fi
    fi
    
    # Set Samba password
    if printf '%s\n%s\n' "$user_pass" "$user_pass" | smbpasswd -a -s "$user_name" >/dev/null 2>&1; then
        log_info "✓ Set Samba password for: '$user_name'"
    else
        log_error "Failed to set Samba password for '$user_name'"
        deluser "$user_name" 2>/dev/null
        delgroup "$user_name" 2>/dev/null
        return 1
    fi
    
    # Enable user (some Samba versions create disabled by default)
    smbpasswd -e "$user_name" >/dev/null 2>&1 || true
    
    # Verify Samba user
    if ! verify_samba_user "$user_name"; then
        log_error "User verification failed for '$user_name'"
        return 1
    fi
    
    # Complete system verification
    if ! verify_user_complete "$user_name" "$user_uid" "$user_gid"; then
        log_warn "Some verification checks failed for '$user_name'"
    fi
    
    return 0
}

# === Secondary Group Processing ===
process_user_secondary_groups() {
    local user_name="$1"
    local i="$2"
    
    local secondary_groups_var="USER_${i}_SECONDARY_GROUPS"
    local secondary_groups="${!secondary_groups_var:-}"
    
    [[ -z "$secondary_groups" ]] && return 0
    
    log_info "Processing secondary groups for '$user_name': $secondary_groups"
    
    IFS=',' read -ra groups <<< "$secondary_groups"
    for group in "${groups[@]}"; do
        group="${group// /}"  # Remove spaces
        [[ -z "$group" ]] && continue
        
        # Check if this is another user's primary group
        if user_exists "$group" && group_exists "$group"; then
            log_info "Adding '$user_name' to user '$group's primary group"
            add_user_to_group "$user_name" "$group"
            continue
        fi
        
        # Check if group exists (could be a defined secondary group or another user's primary group)
        if group_exists "$group"; then
            log_info "Adding '$user_name' to existing group '$group'"
            add_user_to_group "$user_name" "$group"
            continue
        fi
        
        # Group doesn't exist - create it as a new secondary group
        log_info "Group '$group' does not exist, creating it..."
        if create_secondary_group "$group" ""; then
            add_user_to_group "$user_name" "$group"
        else
            log_warn "Failed to create group '$group', skipping"
        fi
    done
}

# === Named Groups Creation ===
create_named_groups() {
    log_info "=== Creating Named Secondary Groups ==="
    
    local group_indices
    group_indices=$(compgen -v SECONDARY_GROUP_ 2>/dev/null | \
        sed 's/SECONDARY_GROUP_//' | \
        sed 's/_NAME$//' | \
        sed 's/_GID$//' | \
        sort -u || true)
    
    [[ -z "$group_indices" ]] && { log_info "No named groups to create"; return 0; }
    
    while IFS= read -r i; do
        local group_name_var="SECONDARY_GROUP_${i}_NAME"
        local group_gid_var="SECONDARY_GROUP_${i}_GID"
        local group_name="${!group_name_var:-}"
        local group_gid="${!group_gid_var:-}"
        
        [[ -z "$group_name" ]] && continue
        
        # Validate GID if provided
        if [[ -n "$group_gid" ]]; then
            if ! group_gid=$(validate_numeric_id "$group_gid" 2>/dev/null); then
                log_warn "Invalid GID for group '$group_name': ${!group_gid_var}, will auto-assign"
                group_gid=""
            fi
        fi
        
        create_secondary_group "$group_name" "$group_gid"
    done <<< "$group_indices"
    
    log_info "✓ Named groups creation complete"
}

# === User Discovery ===
get_user_indices() {
    compgen -v USER_NAME_ 2>/dev/null | sed 's/USER_NAME_//' | sort -n || true
}

# === Main User Processing ===
validate_and_create_users() {
    local user_indices
    user_indices=$(get_user_indices)
    
    if [[ -z "$user_indices" ]]; then
        log_info "No users to create"
        return 0
    fi
    
    log_info "=== Processing Users ==="
    
    # PHASE 1: Create all users (with primary groups only)
    log_info "Phase 1: Creating users and primary groups..."
    
    while IFS= read -r i; do
        local user_name_var="USER_NAME_${i}"
        local user_pass_var="USER_PASS_${i}"
        local user_uid_var="USER_${i}_UID"
        local user_gid_var="USER_${i}_GID"

        local user_name="${!user_name_var:-}"
        local user_pass="${!user_pass_var:-}"

        # Validate we have both username and password
        if [[ -z "$user_name" || -z "$user_pass" ]]; then
            exit_error "Missing USER_NAME_${i} or USER_PASS_${i}"
        fi

        # Check if user already exists
        if user_exists "$user_name"; then
            log_info "User already exists: '$user_name' (skipping)"
            continue
        fi

        # Validate password
        if ! validate_password "$user_pass" "$USER_PASSWORD_MIN_LENGTH" "$USER_PASSWORD_STRICT_MODE"; then
            log_error "Invalid password for user '$user_name'"
            if [[ "$AUTO_CLEANUP_ON_FAILURE" == "1" ]]; then
                continue
            fi
            exit_error "Password validation failed for '$user_name'"
        fi

        # Get UID/GID values
        local user_uid="${!user_uid_var:-}"
        local user_gid="${!user_gid_var:-}"
        
        local uid_valid=false
        local gid_valid=false

        # Validate UID/GID (numeric IDs only)
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

        # Auto-assign UIDs/GIDs if invalid
        case "$uid_valid:$gid_valid" in
            false:false)
                user_uid=$((USER_UID_OFFSET + i))
                user_gid=$user_uid
                log_info "Auto-assigned UID/GID for '$user_name': $user_uid"
                ;;
            false:true)
                user_uid=$user_gid
                log_info "Using GID as UID for '$user_name': $user_uid"
                ;;
            true:false)
                user_gid=$user_uid
                log_info "Using UID as GID for '$user_name': $user_gid"
                ;;
            true:true)
                log_info "Using provided UID/GID for '$user_name': $user_uid/$user_gid"
                ;;
        esac

        # Create the user (primary group only)
        if create_user "$user_name" "$user_pass" "$user_uid" "$user_gid"; then
            log_info "✓ User '$user_name' created successfully"
        else
            log_error "User creation failed: '$user_name'"
            
            if [[ "$AUTO_CLEANUP_ON_FAILURE" == "1" ]]; then
                cleanup_user_on_failure "$user_name" "$user_name" 1
                continue
            fi
            
            # Offer cleanup
            read -p "Remove incomplete user? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup_user_on_failure "$user_name" "$user_name" 1
            fi
            
            exit_error "User creation aborted for '$user_name'"
        fi
    done <<< "$user_indices"
    
    log_info "✓ Phase 1 complete: All users created"
    
    # PHASE 2: Process secondary groups (now all users/groups exist)
    log_info "Phase 2: Processing secondary group memberships..."
    
    while IFS= read -r i; do
        local user_name_var="USER_NAME_${i}"
        local user_name="${!user_name_var:-}"
        
        [[ -z "$user_name" ]] && continue
        
        # Skip if user doesn't exist (creation may have failed)
        if ! user_exists "$user_name"; then
            log_warn "User '$user_name' does not exist, skipping secondary groups"
            continue
        fi
        
        # Process secondary groups for this user
        process_user_secondary_groups "$user_name" "$i"
    done <<< "$user_indices"
    
    log_info "✓ Phase 2 complete: Secondary groups assigned"
    
    # PHASE 3: Show summaries for all users
    log_info "Phase 3: Generating user summaries..."
    
    while IFS= read -r i; do
        local user_name_var="USER_NAME_${i}"
        local user_name="${!user_name_var:-}"
        
        [[ -z "$user_name" ]] && continue
        
        if user_exists "$user_name"; then
            show_user_summary "$user_name"
        fi
    done <<< "$user_indices"
    
    log_info "✓ User creation and configuration complete"
}

# === Guest User Creation ===
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

    local uid_valid=false
    local gid_valid=false

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

    log_info "Creating guest user: '$guest_account' (UID: $guest_uid, GID: $guest_gid)"
    
    addgroup -g "$guest_gid" "$guest_account" || exit_error "Failed to create guest group"
    adduser -D -H -u "$guest_uid" -G "$guest_account" "$guest_account" || exit_error "Failed to create guest user"

    rm -f /etc/samba/guest.acc
    log_info "✓ Guest user created successfully"
}

# === Main Entry Point ===
main() {
    log_info "=== User Creation Started ==="
    log_info "Script: $CONSTRUCT_USER_SCRIPT_NAME v$CONSTRUCT_USER_SCRIPT_VERSION"
    log_info "Timestamp: $(date)"
    
    # Run pre-flight checks
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
    
    # Create users
    validate_and_create_users
    
    # Create guest user if needed
    create_guest_user
    
    log_info "=== User Creation Complete ==="
}

main "$@"