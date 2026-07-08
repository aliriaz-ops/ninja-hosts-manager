#!/bin/bash
# ==============================================================================
# Set-HostsEntry.sh
# Manages /etc/hosts entries on macOS
# Designed for unattended execution via NinjaRMM (runs as root)
#
# Version : 1.0.0
# Author  : Ali Riaz
# GitHub  : https://github.com/aliriaz/ninja-hosts-manager
# License : MIT
#
# Usage:
#   ./Set-HostsEntry.sh -a <Add|Remove|Check> -i <IP> [-h <Hostname>] [-f]
#
# Exit codes:
#   0 = success / entry found (Check)
#   1 = failure / entry not found (Check)
#
# Examples:
#   ./Set-HostsEntry.sh -a Check  -i 192.168.1.10 -h dev.local
#   ./Set-HostsEntry.sh -a Check  -i 192.168.1.10
#   ./Set-HostsEntry.sh -a Add    -i 192.168.1.10 -h dev.local
#   ./Set-HostsEntry.sh -a Add    -i 192.168.1.10 -h dev.local -f
#   ./Set-HostsEntry.sh -a Remove -i 192.168.1.10 -h dev.local
#   ./Set-HostsEntry.sh -a Remove -i 192.168.1.10
#   ./Set-HostsEntry.sh -a Remove -i 192.168.1.10 -f
# ==============================================================================

set -euo pipefail

readonly HOSTS_FILE="/etc/hosts"

# ── Logging ───────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    local message="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts][$level] $message"
}

log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_err()   { log "ERROR" "$1"; }

# ── Validation helpers ────────────────────────────────────────────────────────

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
        log_err "Invalid IP address format: '$ip'"
        exit 1
    fi
}

validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]]; then
        log_err "Invalid hostname format: '$hostname'"
        exit 1
    fi
}

validate_action() {
    local action="$1"
    case "$action" in
        Add|Remove|Check) ;;
        *)
            log_err "Invalid action: '$action'. Must be Add, Remove, or Check."
            exit 1
            ;;
    esac
}

# ── Root check ────────────────────────────────────────────────────────────────

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_err "Script must run as root. Use sudo or run via NinjaRMM."
        exit 1
    fi
}

# ── macOS version-aware DNS flush ─────────────────────────────────────────────

flush_dns() {
    log_info "Detecting macOS version for DNS flush..."

    local os_version
    os_version=$(sw_vers -productVersion)
    local major
    major=$(echo "$os_version" | cut -d. -f1)
    local minor
    minor=$(echo "$os_version" | cut -d. -f2)

    log_info "macOS version: $os_version"

    if [[ "$major" -ge 11 ]]; then
        # Big Sur, Monterey, Ventura, Sonoma and later
        log_info "Flushing DNS (macOS 11+)..."
        dscacheutil -flushcache
        killall -HUP mDNSResponder
    elif [[ "$major" -eq 10 ]]; then
        if [[ "$minor" -ge 12 ]]; then
            # Sierra, High Sierra, Mojave, Catalina
            log_info "Flushing DNS (macOS 10.12–10.15)..."
            killall -HUP mDNSResponder
        elif [[ "$minor" -ge 10 ]]; then
            # Yosemite (10.10.4+)
            log_info "Flushing DNS (macOS 10.10)..."
            dscacheutil -flushcache
            discoveryutil mdnsflushcache 2>/dev/null || true
        else
            log_warn "DNS flush not supported for macOS $os_version — skipping."
        fi
    else
        log_warn "Unrecognised macOS version: $os_version — skipping DNS flush."
    fi

    log_info "DNS flush complete."
}

# ── Backup ────────────────────────────────────────────────────────────────────

create_backup() {
    local stamp
    stamp=$(date '+%Y%m%d_%H%M%S')
    local backup="${HOSTS_FILE}.${stamp}.bak"
    cp -p "$HOSTS_FILE" "$backup"
    log_info "Backup created: $backup"
    echo "$backup"
}

# ── Pattern builder ───────────────────────────────────────────────────────────

build_pattern() {
    local ip="$1"
    local hostname="${2:-}"

    # Escape dots in IP for regex
    local ip_escaped
    ip_escaped=$(echo "$ip" | sed 's/\./\\./g')

    if [[ -n "$hostname" ]]; then
        # Exact IP + hostname match
        echo "^[[:space:]]*${ip_escaped}[[:space:]]+${hostname}([[:space:]]|$)"
    else
        # Any entry starting with this IP
        echo "^[[:space:]]*${ip_escaped}[[:space:]]+"
    fi
}

# ── Entry lookup ──────────────────────────────────────────────────────────────

get_matching_entries() {
    local pattern="$1"
    # Skip comment lines, then match pattern
    grep -v '^\s*#' "$HOSTS_FILE" | grep -E "$pattern" || true
}

# ── Atomic write ──────────────────────────────────────────────────────────────

write_hosts_atomic() {
    local content="$1"
    local tmp
    tmp=$(mktemp "/etc/hosts.XXXXXX.tmp")

    # Ensure temp file is cleaned up on any unexpected exit
    trap 'rm -f "$tmp"' EXIT

    printf '%s\n' "$content" > "$tmp"

    # Preserve original permissions and ownership
    chmod 644 "$tmp"
    chown root:wheel "$tmp"

    # Atomic rename into place
    mv -f "$tmp" "$HOSTS_FILE"

    # Clear trap now that mv succeeded
    trap - EXIT

    log_info "Hosts file written successfully"
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 -a <Add|Remove|Check> -i <IP> [-h <Hostname>] [-f]"
    echo ""
    echo "  -a   Action   : Add, Remove, or Check (required)"
    echo "  -i   IP       : IPv4 address (required)"
    echo "  -h   Hostname : Hostname (required for Add, optional for Remove/Check)"
    echo "  -f   FlushDns : Flush DNS cache after change (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 -a Check  -i 192.168.1.10 -h dev.local"
    echo "  $0 -a Add    -i 192.168.1.10 -h dev.local -f"
    echo "  $0 -a Remove -i 192.168.1.10 -h dev.local"
    echo "  $0 -a Remove -i 192.168.1.10"
    exit 1
}

# ── Parse arguments ───────────────────────────────────────────────────────────

ACTION=""
IP=""
HOSTNAME=""
FLUSH_DNS=false

while getopts ":a:i:h:f" opt; do
    case "$opt" in
        a) ACTION="$OPTARG"   ;;
        i) IP="$OPTARG"       ;;
        h) HOSTNAME="$OPTARG" ;;
        f) FLUSH_DNS=true     ;;
        :)
            log_err "Option -$OPTARG requires an argument."
            usage
            ;;
        \?)
            log_err "Unknown option: -$OPTARG"
            usage
            ;;
    esac
done

# ── Validate required arguments ───────────────────────────────────────────────

[[ -z "$ACTION"   ]] && { log_err "-a (Action) is required."; usage; }
[[ -z "$IP"       ]] && { log_err "-i (IP) is required.";     usage; }

validate_action   "$ACTION"
validate_ip       "$IP"
[[ -n "$HOSTNAME" ]] && validate_hostname "$HOSTNAME"

if [[ "$ACTION" == "Add" && -z "$HOSTNAME" ]]; then
    log_err "-h (Hostname) is required when Action is 'Add'."
    exit 1
fi

# ── Main ──────────────────────────────────────────────────────────────────────

main() {

    check_root

    log_info "========================================"
    log_info "Action   : $ACTION"
    log_info "IP       : $IP"
    log_info "Hostname : ${HOSTNAME:-(any - IP match only)}"
    log_info "FlushDns : $FLUSH_DNS"
    log_info "========================================"

    # Verify hosts file exists
    if [[ ! -f "$HOSTS_FILE" ]]; then
        log_err "Hosts file not found: $HOSTS_FILE"
        exit 1
    fi

    # Build match pattern
    local pattern
    pattern=$(build_pattern "$IP" "$HOSTNAME")

    # ── PRE-CHECK ─────────────────────────────────────────────────────────────
    local matching_entries
    matching_entries=$(get_matching_entries "$pattern")

    local was_present=false
    [[ -n "$matching_entries" ]] && was_present=true

    log_info "----------------------------------------"
    log_info "PRE-CHECK: Entry present = $was_present"

    if [[ "$was_present" == true ]]; then
        while IFS= read -r line; do
            log_info "  Found : '$line'"
        done <<< "$matching_entries"
    else
        log_info "  No matching entries found in hosts file"
    fi
    log_info "----------------------------------------"

    # ── Handle Check — exit without changes ───────────────────────────────────
    if [[ "$ACTION" == "Check" ]]; then
        if [[ "$was_present" == true ]]; then
            log_info "RESULT: FOUND - $IP ${HOSTNAME:-(matched above)}"
            exit 0
        else
            log_info "RESULT: NOT FOUND - $IP ${HOSTNAME:-(no entries for this IP)}"
            exit 1
        fi
    fi

    # ── Skip if already in desired state ──────────────────────────────────────
    local needs_write=false
    case "$ACTION" in
        Add)    [[ "$was_present" == false ]] && needs_write=true ;;
        Remove) [[ "$was_present" == true  ]] && needs_write=true ;;
    esac

    if [[ "$needs_write" == false ]]; then
        case "$ACTION" in
            Add)    log_info "Entry already exists - nothing to add."    ;;
            Remove) log_info "Entry does not exist - nothing to remove." ;;
        esac
        log_info "========================================"
        log_info "RESULT: $ACTION skipped (no-op) for $IP ${HOSTNAME:-}"
        log_info "========================================"
        exit 0
    fi

    # ── Build new hosts content ────────────────────────────────────────────────
    local new_content
    new_content=$(grep -Ev "$pattern" "$HOSTS_FILE" || true)

    if [[ "$ACTION" == "Add" ]]; then
        new_content="${new_content}"$'\n'"${IP}"$'\t'"${HOSTNAME}"
        log_info "Appending new entry: '$IP	$HOSTNAME'"
    fi

    # ── Backup ────────────────────────────────────────────────────────────────
    local backup_path
    backup_path=$(create_backup)

    # ── Write atomically ──────────────────────────────────────────────────────
    if ! write_hosts_atomic "$new_content"; then
        log_warn "Write failed - restoring from backup: $backup_path"
        cp -p "$backup_path" "$HOSTS_FILE"
        log_info "Backup restored successfully"
        exit 1
    fi

    # ── POST-CHECK ────────────────────────────────────────────────────────────
    local final_matches
    final_matches=$(get_matching_entries "$pattern")

    local entry_present=false
    [[ -n "$final_matches" ]] && entry_present=true

    log_info "----------------------------------------"
    log_info "POST-CHECK: Entry present = $entry_present"

    if [[ "$entry_present" == true ]]; then
        while IFS= read -r line; do
            log_info "  Found : '$line'"
        done <<< "$final_matches"
    else
        log_info "  No matching entries found after write"
    fi
    log_info "----------------------------------------"

    # ── Verify outcome ────────────────────────────────────────────────────────
    local success=false
    case "$ACTION" in
        Add)    [[ "$entry_present" == true  ]] && success=true ;;
        Remove) [[ "$entry_present" == false ]] && success=true ;;
    esac

    if [[ "$success" == false ]]; then
        log_err "Verification failed after '$ACTION' for '$IP ${HOSTNAME:-}'"
        exit 1
    fi

    log_info "Verification passed"

    # ── Optional DNS flush ────────────────────────────────────────────────────
    [[ "$FLUSH_DNS" == true ]] && flush_dns

    # ── Done ──────────────────────────────────────────────────────────────────
    log_info "========================================"
    log_info "RESULT: CONFIRMED $ACTION -> $IP ${HOSTNAME:-(all matched entries)}"
    log_info "Backup : $backup_path"
    log_info "========================================"
    exit 0
}

main "$@"
