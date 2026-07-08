#!/bin/bash
# ==============================================================================
# Update-HostsWrapper.sh
# NinjaRMM wrapper to process multiple hosts entries in a single job run.
# Calls Set-HostsEntry.sh for each entry defined in the entries array below.
#
# Version : 1.0.0
# Author  : Ali Riaz
# GitHub  : https://github.com/aliriaz/ninja-hosts-manager
# License : MIT
#
# IMPORTANT:
#   - Shebang MUST be #!/bin/bash — array syntax is not supported by /bin/sh
#   - Set SCRIPT_PATH to wherever Set-HostsEntry.sh lives on the device
#   - Edit the entries array to suit your environment before deploying
# ==============================================================================

SCRIPT_PATH="/usr/local/bin/Set-HostsEntry.sh"

# ── Define entries ─────────────────────────────────────────────────────────────
# Format : "Action IP Hostname"   (Hostname required for Add)
#        : "Action IP"            (Hostname optional for Remove/Check)
# ------------------------------------------------------------------------------
entries=(
    "Add    0.0.0.0  block.example.com"
    "Add    0.0.0.0  ads.example.com"
    "Remove 1.2.3.4  old.internal.local"
    "Remove 5.6.7.8"
)

# ── Logging ───────────────────────────────────────────────────────────────────
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][INFO] $1"; }
log_err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR] $1"; }

# ── Verify Set-HostsEntry.sh is present and executable ───────────────────────
if [[ ! -f "$SCRIPT_PATH" ]]; then
    log_err "Set-HostsEntry.sh not found at: $SCRIPT_PATH"
    log_err "Upload the script to the path above before running this wrapper."
    exit 1
fi

if [[ ! -x "$SCRIPT_PATH" ]]; then
    log_info "Making script executable: $SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# ── Process entries ───────────────────────────────────────────────────────────
total=${#entries[@]}
passed=0
failed=0

log_info "========================================"
log_info "Processing $total entries"
log_info "========================================"

for entry in "${entries[@]}"; do
    read -ra parts <<< "$entry"

    action="${parts[0]}"
    ip="${parts[1]}"
    hostname="${parts[2]:-}"

    log_info "----------------------------------------"
    log_info "Entry: Action=$action | IP=$ip | Hostname=${hostname:-(none)}"

    # Build argument list
    args=(-a "$action" -i "$ip")
    [[ -n "$hostname" ]] && args+=(-h "$hostname")

    # Run and capture output + exit code
    output=$("$SCRIPT_PATH" "${args[@]}" 2>&1)
    exit_code=$?

    echo "$output"

    if [[ "$exit_code" -eq 0 ]]; then
        log_info "Entry result: SUCCESS"
        ((passed++))
    else
        log_err "Entry result: FAILED (exit code $exit_code)"
        ((failed++))
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
log_info "========================================"
log_info "SUMMARY: $total total | $passed passed | $failed failed"
log_info "========================================"

[[ "$failed" -gt 0 ]] && exit 1
exit 0
