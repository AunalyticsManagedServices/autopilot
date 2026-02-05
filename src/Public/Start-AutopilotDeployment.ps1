function Start-AutopilotDeployment {
    <#
    .SYNOPSIS
        Main entry point for Windows Autopilot OOBE deployment.

    .DESCRIPTION
        Orchestrates the complete Autopilot deployment process:
        1. Pre-flight checks (network, modules)
        2. Azure authentication (for Key Vault access)
        3. Certificate retrieval from Key Vault
        4. Microsoft Graph authentication
        5. Device cleanup (Entra, Intune, Autopilot)
        6. AutopilotOOBE registration

        Features:
        - Azure Key Vault integration for secure credentials
        - Retry logic with exponential backoff
        - State machine for resumable deployments
        - Structured logging

    .PARAMETER ConfigPath
        Optional path to configuration file. If not specified, uses default locations.

    .PARAMETER SkipCleanup
        Skip device cleanup phase (not recommended for production).

    .PARAMETER SkipGroupValidation
        Skip Entra group validation.

    .PARAMETER Force
        Force fresh start, ignoring any saved state.

    .EXAMPLE
        Start-AutopilotDeployment

    .EXAMPLE
        Start-AutopilotDeployment -ConfigPath 'C:\Config\autopilot.config.psd1'

    .EXAMPLE
        Start-AutopilotDeployment -SkipCleanup -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [switch]$SkipCleanup,

        [Parameter()]
        [switch]$SkipGroupValidation,

        [Parameter()]
        [switch]$Force
    )

    #Requires -RunAsAdministrator

    # Initialize state
    $statePath = Join-Path $env:TEMP 'Autopilot-DeploymentState.xml'
    $state = [DeploymentState]::new($statePath)

    if ($Force) {
        $state.Reset()
    }

    if ($state.IsResume) {
        Write-Host "Resuming previous deployment from phase: $($state.CurrentPhase)" -ForegroundColor Cyan
    }

    # Start transcript logging
    $transcriptPath = Join-Path $env:TEMP "AutopilotOOBE_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath -Force | Out-Null

    try {
        # ==================== INITIALIZATION ====================
        Clear-Host

        # Setup PowerShell environment
        Set-ExecutionPolicy Unrestricted -Scope Process -Force -ErrorAction SilentlyContinue
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue

        # Ensure NuGet provider
        if ((Get-PackageProvider).Name -notcontains 'NuGet') {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }

        # Install PSWriteColor for banner (if not present)
        if (-not (Get-Module -Name 'PSWriteColor' -ListAvailable)) {
            Install-Module -Name 'PSWriteColor' -Force -ErrorAction SilentlyContinue
        }
        Import-Module 'PSWriteColor' -Force -ErrorAction SilentlyContinue

        # Show banner
        Show-AutopilotBanner

        Write-Host "Transcript: $transcriptPath" -ForegroundColor DarkGray
        Write-Host ""

        # ==================== LOAD CONFIGURATION ====================
        $state.AdvanceTo([DeploymentPhase]::PreFlightChecks)

        Write-AutopilotLog -Level Info -Message "Loading configuration" -Phase 'Init'
        $config = Get-AutopilotConfig -ConfigPath $ConfigPath

        # Cache config in module scope
        $script:Config = $config

        # ==================== PRE-FLIGHT CHECKS ====================
        if (-not $state.ShouldSkip([DeploymentPhase]::PreFlightChecks)) {
            Write-Host "Running pre-flight checks..." -ForegroundColor White
            Write-Host ""

            # Network connectivity
            Write-Host "Checking network connectivity:" -ForegroundColor Yellow
            if (-not (Test-NetworkConnectivity)) {
                throw "Network connectivity check failed. Please ensure you have internet access."
            }
            Write-Host ""

            $state.RecordPhaseResult([DeploymentPhase]::PreFlightChecks, $true)
        }

        # ==================== MODULE INSTALLATION ====================
        $state.AdvanceTo([DeploymentPhase]::ModuleInstallation)

        if (-not $state.ShouldSkip([DeploymentPhase]::ModuleInstallation)) {
            $moduleResult = Test-RequiredModules -AutoInstall
            if (-not $moduleResult.AllPresent) {
                throw "Failed to install required modules"
            }

            # Disable WAM broker BEFORE importing Az modules to prevent
            # Azure.Identity.Broker DLL from loading and causing
            # SharedTokenCacheCredentialBrokerOptions errors during OOBE
            $env:AZURE_BROKER_ENABLED = '0'
            try { Update-AzConfig -EnableLoginByWam $false -LoginExperienceV2 'Off' -ErrorAction SilentlyContinue | Out-Null } catch { }

            # Import modules
            Write-AutopilotLog -Level Info -Message "Importing modules" -Phase 'Modules'
            Import-Module 'Microsoft.Graph.Authentication' -Force
            Import-Module 'Microsoft.Graph.Groups' -Force
            Import-Module 'Microsoft.Graph.Identity.DirectoryManagement' -Force
            Import-Module 'Microsoft.Graph.DeviceManagement.Enrollment' -Force
            Import-Module 'Microsoft.Graph.DeviceManagement' -Force
            Import-Module 'Az.Accounts' -Force
            Import-Module 'Az.KeyVault' -Force
            Import-Module 'AutopilotOOBE' -Force

            Write-Host ""
            $state.RecordPhaseResult([DeploymentPhase]::ModuleInstallation, $true)
        }

        # ==================== WAM BYPASS ====================
        Write-AutopilotLog -Level Info -Message "Disabling Web Account Manager (WAM)" -Phase 'Init'
        Set-WAMState -Enabled $false

        # ==================== AZURE AUTHENTICATION ====================
        $state.AdvanceTo([DeploymentPhase]::AzureAuthentication)

        if (-not $state.ShouldSkip([DeploymentPhase]::AzureAuthentication)) {
            Write-Host ""
            $azContext = Connect-AzureKeyVault -SubscriptionId $config.KeyVault.SubscriptionId -TenantId $config.TenantId
            $state.RecordPhaseResult([DeploymentPhase]::AzureAuthentication, $true)
        }

        # ==================== KEY VAULT ACCESS ====================
        $state.AdvanceTo([DeploymentPhase]::KeyVaultAccess)

        Write-Host ""
        Write-AutopilotLog -Level Info -Message "Retrieving certificate from Key Vault" -Phase 'KeyVault'
        $cert = Get-CertificateFromKeyVault `
            -VaultName $config.KeyVault.Name `
            -CertSecretName $config.KeyVault.CertSecretName `
            -PasswordSecretName $config.KeyVault.PasswordSecretName `
            -AzureContext $azContext

        $state.RecordPhaseResult([DeploymentPhase]::KeyVaultAccess, $true)

        # ==================== GRAPH AUTHENTICATION ====================
        $state.AdvanceTo([DeploymentPhase]::GraphAuthentication)

        Write-Host ""
        if (-not (Test-GraphConnection)) {
            Connect-GraphWithCertificate `
                -TenantId $config.TenantId `
                -ClientId $config.ClientId `
                -Certificate $cert
        }
        else {
            Write-AutopilotLog -Level Info -Message "Already connected to Microsoft Graph" -Phase 'GraphAuth'
        }

        # Clear certificate from memory
        $cert = $null
        [System.GC]::Collect()

        $state.RecordPhaseResult([DeploymentPhase]::GraphAuthentication, $true)

        # ==================== DEVICE INFO ====================
        Write-Host ""
        $deviceInfo = Get-DeviceIdentifiers
        Write-Host "Device: $($deviceInfo.Manufacturer) $($deviceInfo.Model)" -ForegroundColor Cyan
        Write-Host "Serial: $($deviceInfo.SerialNumber)" -ForegroundColor Cyan
        Write-Host ""

        # ==================== DEVICE CLEANUP ====================
        if (-not $SkipCleanup -and $config.CleanupExistingDevices) {
            $state.AdvanceTo([DeploymentPhase]::DeviceCleanup)

            Write-Host "========== DEVICE CLEANUP ==========" -ForegroundColor Cyan

            # Entra cleanup
            $state.AdvanceTo([DeploymentPhase]::EntraCleanup)
            $entraRemoved = Remove-EntraDeviceRecords -State $state

            # Intune cleanup
            $state.AdvanceTo([DeploymentPhase]::IntuneCleanup)
            $intuneRemoved = Remove-IntuneDeviceRecords -State $state

            # Autopilot cleanup
            $state.AdvanceTo([DeploymentPhase]::AutopilotCleanup)
            $autopilotRemoved = Remove-AutopilotRegistration -State $state

            $totalRemoved = $entraRemoved + $intuneRemoved + $autopilotRemoved
            if ($totalRemoved -gt 0) {
                Write-Host "Device cleanup complete. Removed $totalRemoved record(s)." -ForegroundColor Green
            }
            else {
                Write-Host "Device cleanup complete. No existing records found." -ForegroundColor Green
            }
            Write-Host "====================================" -ForegroundColor Cyan
            Write-Host ""

            $state.RecordPhaseResult([DeploymentPhase]::DeviceCleanup, @{
                EntraRemoved     = $entraRemoved
                IntuneRemoved    = $intuneRemoved
                AutopilotRemoved = $autopilotRemoved
            })
        }

        # ==================== GROUP VALIDATION ====================
        $state.AdvanceTo([DeploymentPhase]::GroupValidation)

        if (-not $SkipGroupValidation -and -not $config.SkipGroupValidation) {
            $groupsToValidate = $config.GroupOptions
            if ($groupsToValidate -and $groupsToValidate.Count -gt 0) {
                Test-EntraGroupExists -GroupNames $groupsToValidate | Out-Null
            }
            Write-Host ""
        }

        $state.RecordPhaseResult([DeploymentPhase]::GroupValidation, $true)

        # ==================== LAUNCH AUTOPILOT OOBE ====================
        $state.AdvanceTo([DeploymentPhase]::DeviceRegistration)

        # Set time zone
        if ($config.TimeZone) {
            Write-AutopilotLog -Level Info -Message "Setting time zone: $($config.TimeZone)" -Phase 'Registration'
            try {
                Set-TimeZone -Id $config.TimeZone -ErrorAction Stop
            }
            catch {
                Write-AutopilotLog -Level Warning -Message "Failed to set time zone" -Phase 'Registration'
            }
        }

        $state.AdvanceTo([DeploymentPhase]::OOBELaunch)

        # Re-enable WAM before AutopilotOOBE - it uses its own interactive
        # Graph auth which requires WAM. Our Key Vault auth is already done.
        Write-AutopilotLog -Level Info -Message "Restoring WAM for AutopilotOOBE interactive auth" -Phase 'Enrollment'
        Set-WAMState -Enabled $true

        Register-AutopilotDevice -Config $config

        # ==================== COMPLETION ====================
        $state.MarkCompleted()

        Write-AutopilotLog -Level Info -Message "Autopilot deployment completed successfully" -Phase 'Complete'
    }
    catch {
        Write-Host ""
        Write-Host "==================== ERROR ====================" -ForegroundColor Red
        Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Magenta
        Write-Host "Type: $($_.Exception.GetType().FullName)" -ForegroundColor Magenta
        Write-Host "Message: $($_.Exception.Message)" -ForegroundColor White
        Write-Host "===============================================" -ForegroundColor Red

        $state.RecordError($_.Exception.Message)

        # Troubleshooting hints
        $errorMessage = $_.Exception.Message
        Show-TroubleshootingHints -ErrorMessage $errorMessage

        Write-Host ""
        Write-Host "Transcript: $transcriptPath" -ForegroundColor Yellow

        throw
    }
    finally {
        try {
            $cert = $null
            [System.GC]::Collect()
            Set-WAMState -Enabled $true -ErrorAction SilentlyContinue
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Untrusted -ErrorAction SilentlyContinue | Out-Null
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        }
        catch { }
    }
}

# Helper function to show troubleshooting hints
function Show-TroubleshootingHints {
    param([string]$ErrorMessage)

    Write-Host ""

    if ($ErrorMessage -match 'certificate|pfx|base64|Key Vault') {
        Write-Host "TROUBLESHOOTING: Certificate/Key Vault issue detected" -ForegroundColor Cyan
        Write-Host "  1. Verify Azure Key Vault name is correct" -ForegroundColor White
        Write-Host "  2. Check that secrets exist in Key Vault" -ForegroundColor White
        Write-Host "  3. Ensure you have access to the Key Vault" -ForegroundColor White
        Write-Host "  4. Verify the certificate hasn't expired" -ForegroundColor White
    }
    elseif ($ErrorMessage -match 'Network|connection|timeout') {
        Write-Host "TROUBLESHOOTING: Network issue detected" -ForegroundColor Cyan
        Write-Host "  1. Verify the device has internet access" -ForegroundColor White
        Write-Host "  2. Check if firewall is blocking HTTPS (port 443)" -ForegroundColor White
        Write-Host "  3. Try again - transient network issues are common" -ForegroundColor White
    }
    elseif ($ErrorMessage -match 'permission|unauthorized|forbidden|403|AADSTS') {
        Write-Host "TROUBLESHOOTING: Permission issue detected" -ForegroundColor Cyan
        Write-Host "  1. Verify App Registration has required API permissions" -ForegroundColor White
        Write-Host "  2. Ensure admin consent was granted" -ForegroundColor White
        Write-Host "  3. Check certificate is uploaded to App Registration" -ForegroundColor White
    }
    elseif ($ErrorMessage -match 'configuration|config') {
        Write-Host "TROUBLESHOOTING: Configuration issue detected" -ForegroundColor Cyan
        Write-Host "  1. Verify config file exists and is valid PowerShell data" -ForegroundColor White
        Write-Host "  2. Check all required fields are present" -ForegroundColor White
        Write-Host "  3. See config/autopilot.config.sample.psd1 for reference" -ForegroundColor White
    }
}

# Banner display function
function Show-AutopilotBanner {
    Write-Host ""
    Write-Host '   ___        _              _ _       _   ' -ForegroundColor Cyan
    Write-Host '  / _ \      | |            (_) |     | |  ' -ForegroundColor Cyan
    Write-Host ' / /_\ \_   _| |_ ___  _ __  _| | ___ | |_ ' -ForegroundColor White
    Write-Host ' |  _  | | | | __/ _ \| `_ \| | |/ _ \| __|' -ForegroundColor White
    Write-Host ' | | | | |_| | || (_) | |_) | | | (_) | |_ ' -ForegroundColor Cyan
    Write-Host ' \_| |_/\__,_|\__\___/| .__/|_|_|\___/ \__|' -ForegroundColor Cyan
    Write-Host '                      | |                  ' -ForegroundColor White
    Write-Host '                      |_|                  ' -ForegroundColor White
    Write-Host ""
    Write-Host "Autopilot OOBE Deployment v6.0" -ForegroundColor White
    Write-Host "Azure Key Vault | Retry Logic | Structured Logging" -ForegroundColor DarkGray
    Write-Host ""
}
