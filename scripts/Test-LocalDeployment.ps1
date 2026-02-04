<#
.SYNOPSIS
    Test script for local development and validation.

.DESCRIPTION
    Runs the Autopilot deployment in test mode, validating:
    - Configuration loading
    - Module imports
    - Prerequisites check

    Does NOT perform actual device cleanup or registration unless -Force is specified.

.PARAMETER ConfigPath
    Path to configuration file.

.PARAMETER Force
    Actually run the deployment (not just validation).

.PARAMETER SkipCleanup
    Skip device cleanup phase.

.EXAMPLE
    .\Test-LocalDeployment.ps1
    .\Test-LocalDeployment.ps1 -Force
    .\Test-LocalDeployment.ps1 -ConfigPath '..\config\autopilot.config.psd1'

.NOTES
    Run this from the scripts directory or adjust paths accordingly.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'

# Determine paths
$ScriptRoot = $PSScriptRoot
$ModuleRoot = Join-Path (Split-Path $ScriptRoot -Parent) 'src'
$DefaultConfigPath = Join-Path (Split-Path $ScriptRoot -Parent) 'config\autopilot.config.psd1'

Write-Host ""
Write-Host "Autopilot Local Test" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Module Path: $ModuleRoot" -ForegroundColor DarkGray
Write-Host "Config Path: $($ConfigPath ?? $DefaultConfigPath)" -ForegroundColor DarkGray
Write-Host ""

# Import the module
try {
    Write-Host "Importing Autopilot module..." -ForegroundColor Yellow
    Import-Module "$ModuleRoot\Autopilot.psd1" -Force -ErrorAction Stop
    Write-Host "Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Host "Failed to import module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Determine actual config path
if (-not $ConfigPath) {
    if (Test-Path $DefaultConfigPath) {
        $ConfigPath = $DefaultConfigPath
    }
    else {
        Write-Host "Configuration file not found at: $DefaultConfigPath" -ForegroundColor Red
        Write-Host "Please create a config file or specify -ConfigPath" -ForegroundColor Yellow
        Write-Host "See config\autopilot.config.sample.psd1 for reference" -ForegroundColor Yellow
        exit 1
    }
}

if ($Force) {
    # Run full deployment
    Write-Host "Running FULL deployment (Force mode)" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C within 5 seconds to cancel..." -ForegroundColor Red
    Start-Sleep -Seconds 5

    $params = @{
        ConfigPath = $ConfigPath
    }
    if ($SkipCleanup) {
        $params['SkipCleanup'] = $true
    }

    Start-AutopilotDeployment @params
}
else {
    # Run prerequisites check only
    Write-Host "Running prerequisites check (use -Force for full deployment)" -ForegroundColor Yellow
    Write-Host ""

    Test-AutopilotPrerequisites -ConfigPath $ConfigPath -AutoFix
}
