<#
.SYNOPSIS
    Manages hosts file entries. Designed for unattended execution via NinjaRMM.

.DESCRIPTION
    Adds, removes, or checks IP/hostname mappings in the Windows hosts file.
    - Add    : requires both -IP and -Hostname
    - Remove : -Hostname optional; omitting it removes ALL entries for that IP
    - Check  : returns current state without making any changes

.EXAMPLE
    .\Set-HostsEntry.ps1 -Action Check -IP 192.168.1.10 -Hostname dev.local
    .\Set-HostsEntry.ps1 -Action Check -IP 192.168.1.10
    .\Set-HostsEntry.ps1 -Action Add -IP 192.168.1.10 -Hostname dev.local
    .\Set-HostsEntry.ps1 -Action Add -IP 192.168.1.10 -Hostname dev.local -FlushDns
    .\Set-HostsEntry.ps1 -Action Remove -IP 192.168.1.10 -Hostname dev.local
    .\Set-HostsEntry.ps1 -Action Remove -IP 192.168.1.10

.NOTES
    Version  : 1.0.0
    Author   : Ali Riaz
    GitHub   : https://github.com/aliriaz/ninja-hosts-manager
    License  : MIT

    - Runs as SYSTEM under NinjaRMM (no interactive prompts, no admin check needed)
    - Exit 0 = success / entry found (Check)
    - Exit 1 = failure / entry not found (Check)
    - All output goes to stdout for Ninja activity log
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('Add', 'Remove', 'Check')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidatePattern(
        '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
    )]
    [string]$IP,

    [Parameter()]
    [ValidatePattern('^(?!-)[a-zA-Z0-9\-]{1,63}(?<!-)(\.[a-zA-Z0-9\-]{1,63})*$')]
    [string]$Hostname,

    [switch]$FlushDns
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Logging ───────────────────────────────────────────────────────────────

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}

function Write-Info  { param([string]$m) Write-Log -Level INFO  -Message $m }
function Write-Warn  { param([string]$m) Write-Log -Level WARN  -Message $m }
function Write-Err   { param([string]$m) Write-Log -Level ERROR -Message $m }

#endregion

#region ── Helpers ───────────────────────────────────────────────────────────────

function New-TimestampedBackup {
    param([string]$Path)
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = '{0}.{1}.bak' -f $Path, $stamp
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    Write-Info "Backup created: $backup"
    return $backup
}

function Write-HostsFileAtomic {
    <#
        Writes to a temp file alongside the hosts file then renames into place.
        Prevents a partial-write window where the hosts file would be empty.
    #>
    param(
        [string]$HostsPath,
        [string[]]$Lines
    )
    $tmp = '{0}.{1}.tmp' -f $HostsPath, [System.IO.Path]::GetRandomFileName()
    try {
        [System.IO.File]::WriteAllLines(
            $tmp,
            $Lines,
            [System.Text.Encoding]::ASCII
        )
        Move-Item -LiteralPath $tmp -Destination $HostsPath -Force
    } catch {
        if (Test-Path $tmp) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Get-EntryPattern {
    <#
        Returns a regex that matches the target line(s) in the hosts file.
        If Hostname is provided  -> matches only that exact IP + hostname pair.
        If Hostname is omitted   -> matches any line starting with that IP.
    #>
    param(
        [string]$IP,
        [string]$Hostname
    )
    $ipEsc = [regex]::Escape($IP)
    if ($Hostname) {
        $hostEsc = [regex]::Escape($Hostname)
        return "^\s*$ipEsc\s+$hostEsc(\s|$)"
    } else {
        return "^\s*$ipEsc\s+"
    }
}

function Get-MatchingEntries {
    <#
        Returns all lines from the hosts file that match the pattern.
        Skips comment lines entirely.
    #>
    param(
        [string[]]$Lines,
        [string]$Pattern
    )
    $Lines | Where-Object {
        $_ -notmatch '^\s*#' -and $_ -match $Pattern
    }
}

#endregion

#region ── Main ──────────────────────────────────────────────────────────────────

try {

    # ── Validate intent ───────────────────────────────────────────────────────
    if ($Action -eq 'Add' -and -not $Hostname) {
        throw "Parameter -Hostname is required when Action is 'Add'."
    }

    if ($Action -eq 'Check' -and -not $Hostname) {
        Write-Info "No -Hostname provided — will check for any entry matching IP: $IP"
    }

    # ── Setup ─────────────────────────────────────────────────────────────────
    $hostsPath    = "$env:windir\System32\drivers\etc\hosts"
    $entryPattern = Get-EntryPattern -IP $IP -Hostname $Hostname

    Write-Info "========================================"
    Write-Info "Action   : $Action"
    Write-Info "IP       : $IP"
    Write-Info "Hostname : $(if ($Hostname) { $Hostname } else { '(any - IP match only)' })"
    Write-Info "FlushDns : $($FlushDns.IsPresent)"
    Write-Info "========================================"

    # ── Verify hosts file is accessible ───────────────────────────────────────
    if (-not (Test-Path $hostsPath)) {
        throw "Hosts file not found: $hostsPath"
    }

    # ── Read current content ──────────────────────────────────────────────────
    $originalLines = [System.IO.File]::ReadAllLines($hostsPath)
    Write-Info "Read $($originalLines.Count) lines from hosts file"

    # ── Always check first ────────────────────────────────────────────────────
    $matchingEntries = Get-MatchingEntries -Lines $originalLines -Pattern $entryPattern
    $wasPresent      = ($matchingEntries | Measure-Object).Count -gt 0

    Write-Info "----------------------------------------"
    Write-Info "PRE-CHECK: Entry present = $wasPresent"

    if ($wasPresent) {
        foreach ($match in $matchingEntries) {
            Write-Info "  Found : '$match'"
        }
    } else {
        Write-Info "  No matching entries found in hosts file"
    }
    Write-Info "----------------------------------------"

    # ── Handle Check action — exit here, no changes ───────────────────────────
    if ($Action -eq 'Check') {
        if ($wasPresent) {
            Write-Info "RESULT: FOUND - $IP $(if ($Hostname) { $Hostname } else { '(matched above)' })"
            exit 0
        } else {
            Write-Info "RESULT: NOT FOUND - $IP $(if ($Hostname) { $Hostname } else { '(no entries for this IP)' })"
            exit 1
        }
    }

    # ── Skip if already in desired state ──────────────────────────────────────
    $needsWrite = switch ($Action) {
        'Add'    { -not $wasPresent }
        'Remove' { $wasPresent      }
    }

    if (-not $needsWrite) {
        $reason = switch ($Action) {
            'Add'    { "Entry already exists - nothing to add."    }
            'Remove' { "Entry does not exist - nothing to remove." }
        }
        Write-Info $reason
        Write-Info "========================================"
        Write-Info "RESULT: $Action skipped (no-op) for $IP $(if ($Hostname) { $Hostname })"
        Write-Info "========================================"
        exit 0
    }

    # ── Build filtered line list ───────────────────────────────────────────────
    $filtered = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $originalLines) {
        if ($line -notmatch $entryPattern) {
            $filtered.Add($line)
        }
    }

    # ── Append new entry if adding ────────────────────────────────────────────
    if ($Action -eq 'Add') {
        $newEntry = "$IP`t$Hostname"
        $filtered.Add($newEntry)
        Write-Info "Appending new entry: '$newEntry'"
    }

    # ── Backup ────────────────────────────────────────────────────────────────
    $backupPath = New-TimestampedBackup -Path $hostsPath

    # ── Write atomically ──────────────────────────────────────────────────────
    try {
        Write-HostsFileAtomic -HostsPath $hostsPath -Lines $filtered.ToArray()
        Write-Info "Hosts file written successfully"
    } catch {
        Write-Warn "Write failed - restoring from backup: $backupPath"
        Copy-Item -LiteralPath $backupPath -Destination $hostsPath -Force
        Write-Info "Backup restored successfully"
        throw
    }

    # ── Post-write verification ────────────────────────────────────────────────
    $finalLines   = [System.IO.File]::ReadAllLines($hostsPath)
    $finalMatches = Get-MatchingEntries -Lines $finalLines -Pattern $entryPattern
    $entryPresent = ($finalMatches | Measure-Object).Count -gt 0

    $success = switch ($Action) {
        'Add'    { $entryPresent      }
        'Remove' { -not $entryPresent }
    }

    Write-Info "----------------------------------------"
    Write-Info "POST-CHECK: Entry present = $entryPresent"

    if ($entryPresent) {
        foreach ($match in $finalMatches) {
            Write-Info "  Found : '$match'"
        }
    } else {
        Write-Info "  No matching entries found after write"
    }
    Write-Info "----------------------------------------"

    if (-not $success) {
        throw "Verification failed after '$Action' for '$IP $(if ($Hostname) { $Hostname })'"
    }

    Write-Info "Verification passed"

    # ── Optional DNS flush ────────────────────────────────────────────────────
    if ($FlushDns) {
        Write-Info "Flushing DNS resolver cache..."
        $flushOutput = & ipconfig /flushdns 2>&1
        Write-Info $flushOutput
    }

    # ── Success ───────────────────────────────────────────────────────────────
    Write-Info "========================================"
    Write-Info "RESULT: CONFIRMED $Action -> $IP $(if ($Hostname) { $Hostname } else { '(all matched entries)' })"
    Write-Info "Backup : $backupPath"
    Write-Info "========================================"
    exit 0

} catch {
    Write-Err "========================================"
    Write-Err "Exception  : $_"
    Write-Err "Stack trace: $($_.ScriptStackTrace)"
    Write-Err "========================================"
    exit 1
}

#endregion
