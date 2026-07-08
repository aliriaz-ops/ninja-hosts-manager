# NinjaRMM Hosts File Manager

A cross-platform set of scripts to manage `/etc/hosts` (macOS) and `C:\Windows\System32\drivers\etc\hosts` (Windows) entries remotely via [NinjaRMM](https://www.ninjaone.com/).

Built for real-world RMM deployment — not just a one-liner wrapper.

---

## Features

- ✅ **Add, Remove, or Check** host entries
- ✅ **Pre-check & post-check** verification on every run
- ✅ **Atomic writes** — temp file + rename, no partial-write window
- ✅ **Timestamped backups** before every change
- ✅ **Auto-rollback** if write fails
- ✅ **IP-only wildcard remove** — remove all hostnames mapped to an IP without knowing them
- ✅ **Comment-line aware** — skips `# comment` lines during matching
- ✅ **DNS cache flush** (optional) — version-aware on macOS
- ✅ **NinjaRMM-safe** — runs as SYSTEM (Windows) / root (macOS), no interactive prompts, exit codes for job status
- ✅ **Input validation** — IPv4 format and RFC-1123 hostname checked before touching the file

---

## Platform Support

| Platform | Script | Shell/Runtime |
|---|---|---|
| Windows 10/11, Server 2016+ | `windows/Set-HostsEntry.ps1` | PowerShell 5.1+ |
| macOS 10.12+ (Sierra and later) | `macos/Set-HostsEntry.sh` | bash / zsh |

---

## Usage

### Windows (PowerShell)

```powershell
# Check if an entry exists (no changes made)
.\Set-HostsEntry.ps1 -Action Check -IP 192.168.1.10 -Hostname dev.local

# Check all entries for an IP
.\Set-HostsEntry.ps1 -Action Check -IP 192.168.1.10

# Add an entry
.\Set-HostsEntry.ps1 -Action Add -IP 192.168.1.10 -Hostname dev.local

# Add and flush DNS
.\Set-HostsEntry.ps1 -Action Add -IP 192.168.1.10 -Hostname dev.local -FlushDns

# Remove a specific pair
.\Set-HostsEntry.ps1 -Action Remove -IP 192.168.1.10 -Hostname dev.local

# Remove ALL entries for an IP
.\Set-HostsEntry.ps1 -Action Remove -IP 192.168.1.10
```

### macOS (bash)

```bash
# Check if an entry exists (no changes made)
sudo ./Set-HostsEntry.sh -a Check -i 192.168.1.10 -h dev.local

# Check all entries for an IP
sudo ./Set-HostsEntry.sh -a Check -i 192.168.1.10

# Add an entry
sudo ./Set-HostsEntry.sh -a Add -i 192.168.1.10 -h dev.local

# Add and flush DNS
sudo ./Set-HostsEntry.sh -a Add -i 192.168.1.10 -h dev.local -f

# Remove a specific pair
sudo ./Set-HostsEntry.sh -a Remove -i 192.168.1.10 -h dev.local

# Remove ALL entries for an IP
sudo ./Set-HostsEntry.sh -a Remove -i 192.168.1.10
```

---

## Parameters

### Windows (`Set-HostsEntry.ps1`)

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Action` | String | Yes | `Add`, `Remove`, or `Check` |
| `-IP` | String | Yes | Valid IPv4 address |
| `-Hostname` | String | Add: Yes / Remove+Check: No | RFC-1123 hostname |
| `-FlushDns` | Switch | No | Flush DNS cache after change |

### macOS (`Set-HostsEntry.sh`)

| Flag | Required | Description |
|---|---|---|
| `-a` | Yes | Action: `Add`, `Remove`, or `Check` |
| `-i` | Yes | Valid IPv4 address |
| `-h` | Add: Yes / Remove+Check: No | RFC-1123 hostname |
| `-f` | No | Flush DNS cache after change |

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success / Entry found (Check) |
| `1` | Failure / Entry not found (Check) |

---

## NinjaRMM Deployment

### Windows

1. Go to **Administration → Scripting → Scripts** in Ninja
2. Upload `windows/Set-HostsEntry.ps1`
3. In your automation or device activity, set parameters:

```
-Action Add -IP 192.168.1.10 -Hostname dev.local -FlushDns
```

Or use Ninja custom fields:

```
-Action "{{custom.hostsAction}}" -IP "{{custom.hostsIP}}" -Hostname "{{custom.hostsHostname}}"
```

### macOS

1. Upload `macos/Set-HostsEntry.sh` to your Ninja script library
2. For multiple entries per run, use the included `macos/Update-HostsWrapper.sh`
3. Set the script language to **Shell** and ensure the shebang is `#!/bin/bash`

> ⚠️ **Important:** Always use `#!/bin/bash` not `#!/bin/sh`. Bash array syntax (`entries=(...)`) is not supported by `sh` and will cause a syntax error on line 1.

---

## Activity Log Output

Every run produces structured, timestamped output visible in the Ninja activity log:

```
[2025-01-15 09:32:11][INFO] ========================================
[2025-01-15 09:32:11][INFO] Action   : Add
[2025-01-15 09:32:11][INFO] IP       : 192.168.1.10
[2025-01-15 09:32:11][INFO] Hostname : dev.local
[2025-01-15 09:32:11][INFO] FlushDns : False
[2025-01-15 09:32:11][INFO] ========================================
[2025-01-15 09:32:11][INFO] PRE-CHECK: Entry present = False
[2025-01-15 09:32:11][INFO]   No matching entries found in hosts file
[2025-01-15 09:32:11][INFO] Appending new entry: '192.168.1.10    dev.local'
[2025-01-15 09:32:11][INFO] Backup created: ...hosts.20250115_093211.bak
[2025-01-15 09:32:11][INFO] Hosts file written successfully
[2025-01-15 09:32:11][INFO] POST-CHECK: Entry present = True
[2025-01-15 09:32:11][INFO]   Found : '192.168.1.10    dev.local'
[2025-01-15 09:32:11][INFO] Verification passed
[2025-01-15 09:32:11][INFO] RESULT: CONFIRMED Add -> 192.168.1.10 dev.local
```

---

## Security Notes

- Scripts **never** prompt for input — safe for unattended RMM execution
- Backups are written to the same directory as the hosts file with a timestamp suffix
- The hosts file is written via atomic rename — a crash mid-write leaves the original intact
- Input is validated with strict regex before any file operation begins

---

## Contributing

Pull requests welcome. Please test against both PowerShell 5.1 and PowerShell 7+ on Windows, and against macOS 12+ for the shell script.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Author

Maintained by [Ali Riaz](https://github.com/aliriaz) — IT Systems & Support Officer  
Built for enterprise RMM deployment at scale.
