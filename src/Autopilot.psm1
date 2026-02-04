#Requires -Version 5.1

<#
.SYNOPSIS
    Autopilot OOBE Deployment Module

.DESCRIPTION
    A modular PowerShell framework for Windows Autopilot deployment with:
    - Azure Key Vault integration for secure credential management
    - Retry logic with exponential backoff
    - Structured logging for troubleshooting
    - State machine for resumable deployments
    - Cached device identifiers

.NOTES
    Version:        6.0.0
    Author:         Aunalytics
#>

# Module-scoped variables
$script:DeviceIdentifiers = $null
$script:DeploymentState = $null
$script:Config = $null
$script:LogPath = $null

# Get the module root path
$ModuleRoot = $PSScriptRoot

# Dot-source all class files first (order matters for inheritance)
$ClassFiles = @(
    'Classes\AutopilotConfig.ps1',
    'Classes\DeploymentResult.ps1',
    'Classes\DeploymentState.ps1'
)

foreach ($file in $ClassFiles) {
    $filePath = Join-Path -Path $ModuleRoot -ChildPath $file
    if (Test-Path -Path $filePath) {
        . $filePath
    }
}

# Dot-source all private functions
$PrivateFolders = @(
    'Private\Utilities',
    'Private\Configuration',
    'Private\Authentication',
    'Private\Validation',
    'Private\DeviceCleanup',
    'Private\Enrollment'
)

foreach ($folder in $PrivateFolders) {
    $folderPath = Join-Path -Path $ModuleRoot -ChildPath $folder
    if (Test-Path -Path $folderPath) {
        $functions = Get-ChildItem -Path $folderPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        foreach ($function in $functions) {
            . $function.FullName
        }
    }
}

# Dot-source all public functions
$PublicPath = Join-Path -Path $ModuleRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {
    $publicFunctions = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    foreach ($function in $publicFunctions) {
        . $function.FullName
    }
}

# Export public functions (also defined in manifest)
Export-ModuleMember -Function @(
    'Start-AutopilotDeployment',
    'Test-AutopilotPrerequisites',
    'Get-AutopilotStatus'
)
