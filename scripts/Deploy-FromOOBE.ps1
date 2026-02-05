<#
.SYNOPSIS
    Bootstrap script for Autopilot OOBE deployment.

.DESCRIPTION
    This is a minimal bootstrap script designed to be executed during Windows OOBE
    via an irm/iex one-liner. It:
    1. Downloads and imports the Autopilot module
    2. Runs the deployment

    Usage (from OOBE):
    irm https://raw.githubusercontent.com/AunalyticsManagedServices/autopilot/main/scripts/Deploy-FromOOBE.ps1 | iex

.NOTES
    Version: 6.0.0
    Requires: -RunAsAdministrator
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Disable WAM broker at the earliest possible point, BEFORE any Az modules load
# Prevents Azure.Identity.Broker DLL from causing SharedTokenCacheCredentialBrokerOptions errors
$env:AZURE_BROKER_ENABLED = '0'

Write-Host ""
Write-Host "Autopilot OOBE Bootstrap" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$RepoZipUrl = 'https://github.com/AunalyticsManagedServices/autopilot/archive/refs/heads/main.zip'
$LocalModulePath = 'C:\Autopilot\src'
$LocalConfigPath = 'C:\Autopilot\config\autopilot.config.psd1'

try {
    # Setup PowerShell environment
    Set-ExecutionPolicy Unrestricted -Scope Process -Force
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

    # Ensure NuGet provider
    if ((Get-PackageProvider).Name -notcontains 'NuGet') {
        Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    # Check for local module first
    if (Test-Path $LocalModulePath) {
        Write-Host "Using local module: $LocalModulePath" -ForegroundColor Green
        Import-Module "$LocalModulePath\Autopilot.psd1" -Force
    }
    else {
        # Download entire repo as zip and extract
        Write-Host "Downloading module from GitHub..." -ForegroundColor Yellow

        $tempDir = Join-Path $env:TEMP 'AutopilotDownload'
        $zipPath = Join-Path $env:TEMP 'autopilot.zip'

        # Clean up any previous downloads
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        # Download and extract
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        # GitHub extracts to autopilot-main/ folder
        $extractedPath = Join-Path $tempDir 'autopilot-main'
        $modulePath = Join-Path $extractedPath 'src'
        $configPath = Join-Path $extractedPath 'config\autopilot.config.psd1'

        Write-Host "Module downloaded and extracted" -ForegroundColor Green

        Import-Module "$modulePath\Autopilot.psd1" -Force

        # Clean up zip
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }

    # Check for local config (override extracted config if local exists)
    if (Test-Path $LocalConfigPath) {
        Write-Host "Using local configuration: $LocalConfigPath" -ForegroundColor Green
        $configPath = $LocalConfigPath
    }
    elseif ($env:AUTOPILOT_CONFIG_PATH -and (Test-Path $env:AUTOPILOT_CONFIG_PATH)) {
        Write-Host "Using environment config: $env:AUTOPILOT_CONFIG_PATH" -ForegroundColor Green
        $configPath = $env:AUTOPILOT_CONFIG_PATH
    }

    # Run deployment
    Write-Host ""
    Write-Host "Starting Autopilot deployment..." -ForegroundColor Green
    Write-Host ""

    if ($configPath) {
        Start-AutopilotDeployment -ConfigPath $configPath
    }
    else {
        Start-AutopilotDeployment
    }
}
catch {
    Write-Host ""
    Write-Host "Bootstrap failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
