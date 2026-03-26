#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Completely removes Microsoft Edge from Windows 10/11 and blocks reinstallation.

.DESCRIPTION
    This script performs the following:
    1. Sets registry keys to allow Edge uninstallation
    2. Kills all running Edge and Edge Update processes
    3. Attempts official uninstall via Edge's setup.exe
    4. Force-removes Edge installation directories
    5. Cleans up shortcuts, scheduled tasks, and residual files
    6. Sets registry keys to block Edge from being reinstalled via Windows Update

.PARAMETER BlockReinstall
    Blocks Windows Update from reinstalling Edge. Enabled by default.

.PARAMETER SkipConfirmation
    Skips the confirmation prompt before removal.

.EXAMPLE
    .\Remove-Edge.ps1
    # Removes Edge with confirmation prompt

.EXAMPLE
    .\Remove-Edge.ps1 -SkipConfirmation
    # Removes Edge without asking for confirmation

.EXAMPLE
    .\Remove-Edge.ps1 -BlockReinstall:$false
    # Removes Edge but does not block reinstallation

.NOTES
    Author: Chirag
    Tested on: Windows 11 Pro (Build 26300+)
    Run this script as Administrator.
#>

[CmdletBinding()]
param(
    [switch]$SkipConfirmation,
    [bool]$BlockReinstall = $true
)

# --- Helpers ---

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$((Get-Date).ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor Red
}

# --- Pre-flight checks ---

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "This script must be run as Administrator."
    Write-Host "  Right-click PowerShell -> Run as Administrator, then try again."
    exit 1
}

$edgePaths = @(
    "$env:ProgramFiles\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\Edge"
)

$edgeInstalled = $false
foreach ($p in $edgePaths) {
    if (Test-Path "$p\Application\msedge.exe") {
        $edgeInstalled = $true
        $edgeRoot = $p
        break
    }
}

if (-not $edgeInstalled) {
    Write-Warn "Microsoft Edge is not installed (msedge.exe not found)."
    if ($BlockReinstall) {
        Write-Step "Applying reinstall block anyway..."
        # Fall through to block reinstall
    } else {
        exit 0
    }
}

# --- Confirmation ---

if ($edgeInstalled -and -not $SkipConfirmation) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host " Microsoft Edge Removal Tool" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "`nThis will:"
    Write-Host "  - Kill all Edge processes"
    Write-Host "  - Remove Microsoft Edge completely"
    Write-Host "  - Clean up shortcuts and scheduled tasks"
    if ($BlockReinstall) {
        Write-Host "  - Block Edge from being reinstalled via Windows Update"
    }
    Write-Host ""
    $confirm = Read-Host "Proceed? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# --- Step 1: Registry - Allow Uninstall ---

if ($edgeInstalled) {
    Write-Step "Setting registry keys to allow Edge uninstall..."

    $regPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev"
    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "AllowUninstall" -Value 1 -Type DWord -Force
        Write-Ok "AllowUninstall = 1"
    } catch {
        Write-Warn "Could not set AllowUninstall: $_"
    }

    # --- Step 2: Kill Edge processes ---

    Write-Step "Stopping Edge processes..."

    $edgeProcesses = @("msedge", "MicrosoftEdgeUpdate", "MicrosoftEdge", "edge", "msedgewebview2")
    foreach ($proc in $edgeProcesses) {
        $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($running) {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Ok "Stopped $proc ($($running.Count) instance(s))"
        }
    }
    Start-Sleep -Seconds 2

    # --- Step 3: Try official uninstaller ---

    Write-Step "Attempting official Edge uninstaller..."

    $setupExe = $null
    $versionDirs = Get-ChildItem "$edgeRoot\Application" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.' }

    foreach ($dir in $versionDirs) {
        $candidate = Join-Path $dir.FullName "Installer\setup.exe"
        if (Test-Path $candidate) {
            $setupExe = $candidate
            break
        }
    }

    if ($setupExe) {
        Write-Host "  Found: $setupExe"
        $proc = Start-Process -FilePath $setupExe `
            -ArgumentList "--uninstall", "--system-level", "--force-uninstall" `
            -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        if ($proc.ExitCode -eq 0) {
            Write-Ok "Official uninstaller succeeded"
        } else {
            Write-Warn "Official uninstaller exited with code $($proc.ExitCode), proceeding with force removal..."
        }
    } else {
        Write-Warn "No setup.exe found, proceeding with force removal..."
    }

    # --- Step 4: Force remove Edge directories ---

    Write-Step "Force-removing Edge directories..."

    $dirsToRemove = @(
        "$env:ProgramFiles\Microsoft\Edge",
        "${env:ProgramFiles(x86)}\Microsoft\Edge",
        "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate",
        "$env:ProgramFiles\Microsoft\EdgeUpdate",
        "${env:ProgramFiles(x86)}\Microsoft\EdgeCore",
        "$env:ProgramFiles\Microsoft\EdgeCore",
        "${env:ProgramFiles(x86)}\Microsoft\Temp"
    )

    foreach ($dir in $dirsToRemove) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
                Write-Ok "Removed $dir"
            } catch {
                Write-Warn "Could not fully remove $dir : $_"
            }
        }
    }

    # --- Step 5: Clean up shortcuts ---

    Write-Step "Cleaning up shortcuts..."

    $shortcuts = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"
    )

    foreach ($s in $shortcuts) {
        if (Test-Path $s) {
            Remove-Item $s -Force -ErrorAction SilentlyContinue
            Write-Ok "Removed $s"
        }
    }

    # --- Step 6: Remove scheduled tasks ---

    Write-Step "Removing Edge scheduled tasks..."

    $edgeTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match 'Edge|MicrosoftEdge' }

    foreach ($task in $edgeTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
            Write-Ok "Removed task: $($task.TaskName)"
        } catch {
            Write-Warn "Could not remove task $($task.TaskName): $_"
        }
    }
    # --- Step 6b: Clean up stale Edge registry entries ---

    Write-Step "Cleaning up Edge registry entries..."

    # Remove Edge client registration (prevents ghost installs blocking reinstalls of other components)
    $edgeClientKeys = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}"
    )

    foreach ($key in $edgeClientKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Ok "Removed $key"
            } catch {
                Write-Warn "Could not remove $key : $_"
            }
        }
    }

    # Remove EdgeUpdate registration if no other Edge products remain (keep if WebView2 is still registered)
    $webview2Key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    $edgeUpdatePaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
    )

    foreach ($euPath in $edgeUpdatePaths) {
        $clientsPath = "$euPath\Clients"
        if (Test-Path $clientsPath) {
            $remaining = Get-ChildItem $clientsPath -ErrorAction SilentlyContinue
            if ($remaining.Count -eq 0) {
                try {
                    Remove-Item -Path $euPath -Recurse -Force -ErrorAction Stop
                    Write-Ok "Removed empty EdgeUpdate tree: $euPath"
                } catch {
                    Write-Warn "Could not remove $euPath : $_"
                }
            } else {
                Write-Ok "Kept $euPath (other products still registered)"
            }
        }
    }

    # Clean up Edge uninstall entries from Add/Remove Programs
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($uPath in $uninstallPaths) {
        if (Test-Path $uPath) {
            Get-ChildItem $uPath -ErrorAction SilentlyContinue | ForEach-Object {
                $displayName = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                if ($displayName -match '^Microsoft Edge$') {
                    try {
                        Remove-Item $_.PSPath -Recurse -Force -ErrorAction Stop
                        Write-Ok "Removed uninstall entry: $displayName"
                    } catch {
                        Write-Warn "Could not remove uninstall entry: $_"
                    }
                }
            }
        }
    }
}

# --- Step 7: Block reinstall ---

if ($BlockReinstall) {
    Write-Step "Blocking Edge reinstallation via Windows Update..."

    # Prevent Edge delivery via Windows Update
    $regPath1 = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
    if (-not (Test-Path $regPath1)) { New-Item -Path $regPath1 -Force | Out-Null }
    Set-ItemProperty -Path $regPath1 -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord -Force
    Write-Ok "DoNotUpdateToEdgeWithChromium = 1"

    # Block via Group Policy equivalent
    $regPath2 = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
    if (-not (Test-Path $regPath2)) { New-Item -Path $regPath2 -Force | Out-Null }
    Set-ItemProperty -Path $regPath2 -Name "InstallDefault" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $regPath2 -Name "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -Type DWord -Force
    Write-Ok "EdgeUpdate install policies set to block"
}

# --- Summary ---

Write-Host "`n========================================" -ForegroundColor Green
$stillExists = $false
foreach ($p in $edgePaths) {
    if (Test-Path "$p\Application\msedge.exe") { $stillExists = $true }
}

if ($stillExists) {
    Write-Fail "Edge may not be fully removed. Some files are locked."
    Write-Host "  Try rebooting and running this script again."
} else {
    Write-Host " Microsoft Edge has been removed!" -ForegroundColor Green
    if ($BlockReinstall) {
        Write-Host " Reinstallation via Windows Update is blocked." -ForegroundColor Green
    }
}
Write-Host "========================================`n" -ForegroundColor Green
