# Microsoft Edge Uninstaller

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-0078D4?style=flat-square&logo=powershell)
![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?style=flat-square&logo=windows)
![License](https://img.shields.io/github/license/Chiragsd13/microsoft-edge-uninstaller?style=flat-square)
![Stars](https://img.shields.io/github/stars/Chiragsd13/microsoft-edge-uninstaller?style=flat-square)

A PowerShell tool to **completely remove Microsoft Edge** from Windows 10/11 and prevent it from being reinstalled via Windows Update.

## Quick Start

```powershell
# Run as Administrator:
irm https://raw.githubusercontent.com/Chiragsd13/microsoft-edge-uninstaller/master/Remove-Edge.ps1 | iex
```

Or clone and run locally:

```powershell
git clone https://github.com/Chiragsd13/microsoft-edge-uninstaller
cd microsoft-edge-uninstaller
.\Remove-Edge.ps1
```

## Why?

Windows makes it nearly impossible to uninstall Edge through normal means — there's no "Uninstall" button in Settings, `winget uninstall` fails with exit code 93, and the built-in `setup.exe` uninstaller is blocked on recent Windows 11 builds. This tool handles all of that.

## What It Does

1. **Sets registry keys** to allow Edge uninstallation (`AllowUninstall`)
2. **Kills all Edge processes** (msedge, EdgeUpdate, EdgeWebView2)
3. **Runs the official uninstaller** via Edge's `setup.exe --force-uninstall`
4. **Force-removes** Edge directories if the official uninstaller fails (common on Win11 26300+)
5. **Cleans up** shortcuts (Start Menu, Desktop, Taskbar) and scheduled tasks
6. **Cleans up stale registry entries** (EdgeUpdate Clients, ClientState, Add/Remove Programs) so ghost registrations don't block WebView2 or other installs
7. **Blocks reinstallation** via registry policies so Windows Update doesn't bring it back

## Usage

### Remove Edge

```powershell
# Open PowerShell as Administrator, then:
.\Remove-Edge.ps1
```

#### Options

| Flag | Description |
|------|-------------|
| `-SkipConfirmation` | Skip the "are you sure?" prompt |
| `-BlockReinstall:$false` | Don't block reinstallation (only removes Edge) |

```powershell
# Remove without confirmation
.\Remove-Edge.ps1 -SkipConfirmation

# Remove but allow reinstallation later
.\Remove-Edge.ps1 -BlockReinstall:$false
```

### Restore Edge (Undo)

If you want Edge back:

```powershell
# Open PowerShell as Administrator, then:
.\Restore-Edge.ps1
```

This removes the reinstall block. After running it, download Edge from [microsoft.com/edge](https://www.microsoft.com/edge) or wait for Windows Update to restore it.

## How It Works

### The Problem

On modern Windows 11 (Build 26300+), Microsoft protects Edge from removal at multiple levels:

- **Settings app**: No uninstall button for Edge
- **winget uninstall**: Fails with exit code 93
- **setup.exe --uninstall**: Blocked by OS policy
- **Remove-AppxPackage**: Returns `0x80073CFA` ("part of Windows")

### The Solution

| Step | Method | Why |
|------|--------|-----|
| 1 | Set `HKLM:\...\EdgeUpdateDev\AllowUninstall = 1` | Tells the Edge uninstaller it's OK to proceed |
| 2 | `Stop-Process` on all Edge processes | Can't delete files that are in use |
| 3 | Run `setup.exe --uninstall --system-level --force-uninstall` | Try the official way first |
| 4 | `Remove-Item -Recurse -Force` on Edge directories | Force removal when official uninstaller fails |
| 5 | Delete shortcuts + `Unregister-ScheduledTask` | Clean up residual artifacts |
| 6 | Remove stale Edge registry entries (Clients, ClientState, Uninstall) | Prevent ghost registrations from blocking WebView2 or other installs |
| 7 | Set `DoNotUpdateToEdgeWithChromium = 1` + EdgeUpdate policies | Prevent Windows Update from reinstalling |

### Registry Keys Used

| Key | Value | Purpose |
|-----|-------|---------|
| `HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev` | `AllowUninstall = 1` | Permits Edge uninstallation |
| `HKLM:\SOFTWARE\Microsoft\EdgeUpdate` | `DoNotUpdateToEdgeWithChromium = 1` | Blocks Edge delivery via Windows Update |
| `HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate` | `InstallDefault = 0` | Blocks Edge auto-install |
| `HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate` | `Install{56EB18F8-...} = 0` | Blocks Edge Stable channel install |

## Important Notes

- **Run as Administrator** — the script will exit if not elevated
- **Edge WebView2 is NOT removed** — many apps depend on it (Teams, Widgets, etc.). Only the Edge browser is removed.
- **Major Windows feature updates** (e.g., 23H2 → 24H2) may reinstall Edge despite the registry blocks. Re-run the script if that happens.
- **This is reversible** — use `Restore-Edge.ps1` to undo everything

## Tested On

- Windows 11 Pro Build 26300 (2025)
- PowerShell 7.x and Windows PowerShell 5.1

## Contributing

PRs welcome. If the script breaks on a new Windows build, open an issue with your build number and the error output.
