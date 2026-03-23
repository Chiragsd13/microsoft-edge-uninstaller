#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reverses the Edge removal — unblocks reinstallation so you can install Edge again.

.DESCRIPTION
    Removes the registry keys that block Edge installation, allowing you to
    reinstall Edge from microsoft.com or via Windows Update.

.NOTES
    Author: Chirag
    Run this script as Administrator.
#>

[CmdletBinding()]
param()

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

Write-Host "`nRemoving Edge reinstall blocks...`n" -ForegroundColor Cyan

# Remove DoNotUpdateToEdgeWithChromium
$path1 = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
if (Test-Path $path1) {
    Remove-ItemProperty -Path $path1 -Name "DoNotUpdateToEdgeWithChromium" -ErrorAction SilentlyContinue
    Write-Ok "Removed DoNotUpdateToEdgeWithChromium"
}

# Remove install block policies
$path2 = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
if (Test-Path $path2) {
    Remove-ItemProperty -Path $path2 -Name "InstallDefault" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $path2 -Name "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -ErrorAction SilentlyContinue
    Write-Ok "Removed EdgeUpdate install policies"
}

Write-Host "`nEdge reinstall is now unblocked." -ForegroundColor Green
Write-Host "You can download Edge from: https://www.microsoft.com/edge`n"
