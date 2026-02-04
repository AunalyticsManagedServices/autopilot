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

Write-Host ""
Write-Host "Autopilot OOBE Bootstrap" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

# Configuration - GitHub raw URLs for the module (public repo)
$ModuleSource = 'https://raw.githubusercontent.com/AunalyticsManagedServices/autopilot/main/src'
$ConfigUrl = 'https://raw.githubusercontent.com/AunalyticsManagedServices/autopilot/main/config/autopilot.config.psd1'

# Alternatively, use local paths if module is pre-staged
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
        # Download module from remote source
        Write-Host "Downloading module from: $ModuleSource" -ForegroundColor Yellow

        $tempModulePath = Join-Path $env:TEMP 'Autopilot'
        if (Test-Path $tempModulePath) {
            Remove-Item $tempModulePath -Recurse -Force
        }
        New-Item -Path $tempModulePath -ItemType Directory -Force | Out-Null

        # Download module files (this is a simplified example - in production,
        # consider using a zip file or proper module repository)
        $files = @(
            'Autopilot.psd1',
            'Autopilot.psm1'
            # Add other files as needed
        )

        foreach ($file in $files) {
            $url = "$ModuleSource/$file"
            $dest = Join-Path $tempModulePath $file
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        }

        Import-Module "$tempModulePath\Autopilot.psd1" -Force
    }

    # Check for local config
    $configPath = $null
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
