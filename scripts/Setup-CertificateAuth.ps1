<#
.SYNOPSIS
    Sets up certificate-based authentication for Autopilot OOBE deployment.

.DESCRIPTION
    This script automates the setup of certificate authentication:
    1. Generates a self-signed certificate
    2. Exports public key (.cer) for App Registration
    3. Exports private key (.pfx) and converts to Base64
    4. Optionally uploads secrets to Azure Key Vault
    5. Optionally uploads certificate to App Registration

    After running this script, the Autopilot module can authenticate to
    Microsoft Graph without any user interaction.

.PARAMETER CertificateName
    Name for the certificate. Default: AutopilotOOBE-Auth

.PARAMETER CertificatePassword
    Password to protect the PFX file. If not provided, will prompt securely.

.PARAMETER ValidYears
    Number of years the certificate should be valid. Default: 2

.PARAMETER KeyVaultName
    Name of the Azure Key Vault to store secrets. Default: from config file.

.PARAMETER SubscriptionId
    Azure subscription ID. Default: from config file.

.PARAMETER TenantId
    Entra ID tenant ID. Default: from config file.

.PARAMETER ClientId
    App Registration client ID. Default: from config file.

.PARAMETER SkipKeyVaultUpload
    Skip uploading secrets to Key Vault (manual upload required).

.PARAMETER SkipAppRegistration
    Skip uploading certificate to App Registration (manual upload required).

.PARAMETER OutputPath
    Directory to save certificate files. Default: Desktop.

.PARAMETER CleanupFiles
    Remove local certificate files after successful Key Vault upload.

.EXAMPLE
    .\Setup-CertificateAuth.ps1
    # Interactive mode - prompts for password, uses config file values

.EXAMPLE
    .\Setup-CertificateAuth.ps1 -CertificatePassword "MySecurePass123!" -CleanupFiles
    # Automated mode with cleanup

.EXAMPLE
    .\Setup-CertificateAuth.ps1 -SkipKeyVaultUpload -SkipAppRegistration
    # Generate certificate only, manual upload required

.NOTES
    Version: 1.0.0
    Requires: PowerShell 5.1+, Administrator rights
    Optional: Az.Accounts, Az.KeyVault modules for automated upload
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string]$CertificateName = 'AutopilotOOBE-Auth',

    [Parameter()]
    [string]$CertificatePassword,

    [Parameter()]
    [int]$ValidYears = 2,

    [Parameter()]
    [string]$KeyVaultName,

    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [switch]$SkipKeyVaultUpload,

    [Parameter()]
    [switch]$SkipAppRegistration,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$CleanupFiles
)

$ErrorActionPreference = 'Stop'

# Banner
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Autopilot Certificate Authentication Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration if available
$scriptRoot = $PSScriptRoot
$configPath = Join-Path (Split-Path $scriptRoot -Parent) 'config\autopilot.config.psd1'

if (Test-Path $configPath) {
    Write-Host "Loading configuration from: $configPath" -ForegroundColor DarkGray
    $config = Import-PowerShellDataFile -Path $configPath

    # Use config values as defaults if not provided
    if (-not $KeyVaultName) { $KeyVaultName = $config.KeyVault.Name }
    if (-not $SubscriptionId) { $SubscriptionId = $config.KeyVault.SubscriptionId }
    if (-not $TenantId) { $TenantId = $config.TenantId }
    if (-not $ClientId) { $ClientId = $config.ClientId }
}

# Validate required parameters
if (-not $KeyVaultName -and -not $SkipKeyVaultUpload) {
    throw "KeyVaultName is required. Provide via parameter or config file."
}

# Set default output path and ensure it exists
if (-not $OutputPath) {
    # Try Desktop first, fall back to TEMP
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    if ($desktopPath -and (Test-Path $desktopPath)) {
        $OutputPath = $desktopPath
    }
    else {
        $OutputPath = $env:TEMP
    }
}

# Ensure output path exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Prompt for password if not provided
if (-not $CertificatePassword) {
    Write-Host "Enter a password to protect the certificate:" -ForegroundColor Yellow
    $securePassword = Read-Host -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $CertificatePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    if ([string]::IsNullOrWhiteSpace($CertificatePassword)) {
        throw "Certificate password cannot be empty"
    }
}

# File paths
$cerPath = Join-Path $OutputPath "$CertificateName.cer"
$pfxPath = Join-Path $OutputPath "$CertificateName.pfx"
$base64Path = Join-Path $OutputPath "$CertificateName-Base64.txt"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Certificate Name: $CertificateName" -ForegroundColor White
Write-Host "  Valid For:        $ValidYears years" -ForegroundColor White
Write-Host "  Key Vault:        $KeyVaultName" -ForegroundColor White
Write-Host "  Subscription:     $SubscriptionId" -ForegroundColor White
Write-Host "  Tenant ID:        $TenantId" -ForegroundColor White
Write-Host "  Client ID:        $ClientId" -ForegroundColor White
Write-Host "  Output Path:      $OutputPath" -ForegroundColor White
Write-Host ""

# ============================================================================
# STEP 1: Generate Certificate
# ============================================================================
Write-Host "Step 1: Generating self-signed certificate..." -ForegroundColor Cyan

$certParams = @{
    Subject           = "CN=$CertificateName"
    CertStoreLocation = "Cert:\CurrentUser\My"
    KeyExportPolicy   = 'Exportable'
    KeySpec           = 'Signature'
    KeyLength         = 2048
    KeyAlgorithm      = 'RSA'
    HashAlgorithm     = 'SHA256'
    NotAfter          = (Get-Date).AddYears($ValidYears)
}

$cert = New-SelfSignedCertificate @certParams

Write-Host "  [OK] Certificate created" -ForegroundColor Green
Write-Host "       Thumbprint: $($cert.Thumbprint)" -ForegroundColor DarkGray
Write-Host "       Expires:    $($cert.NotAfter)" -ForegroundColor DarkGray

# ============================================================================
# STEP 2: Export Public Key (.cer)
# ============================================================================
Write-Host ""
Write-Host "Step 2: Exporting public key (.cer)..." -ForegroundColor Cyan

Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
Write-Host "  [OK] Public key exported to: $cerPath" -ForegroundColor Green

# ============================================================================
# STEP 3: Export Private Key (.pfx) and Convert to Base64
# ============================================================================
Write-Host ""
Write-Host "Step 3: Exporting private key (.pfx) and converting to Base64..." -ForegroundColor Cyan

$securePassword = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePassword | Out-Null
Write-Host "  [OK] PFX exported to: $pfxPath" -ForegroundColor Green

# Convert to Base64
$pfxBytes = [System.IO.File]::ReadAllBytes($pfxPath)
$base64Pfx = [System.Convert]::ToBase64String($pfxBytes)
$base64Pfx | Out-File -FilePath $base64Path -NoNewline -Encoding ASCII
Write-Host "  [OK] Base64 saved to: $base64Path" -ForegroundColor Green

# ============================================================================
# STEP 4: Upload to Azure Key Vault
# ============================================================================
Write-Host ""
if ($SkipKeyVaultUpload) {
    Write-Host "Step 4: Skipping Key Vault upload (manual upload required)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Manual steps:" -ForegroundColor White
    Write-Host "  1. Go to Azure Portal > Key Vaults > $KeyVaultName" -ForegroundColor DarkGray
    Write-Host "  2. Create secret 'AutopilotOOBE-Cert' with contents of:" -ForegroundColor DarkGray
    Write-Host "     $base64Path" -ForegroundColor DarkGray
    Write-Host "  3. Create secret 'AutopilotOOBE-Cert-Password' with value:" -ForegroundColor DarkGray
    Write-Host "     (the password you entered)" -ForegroundColor DarkGray
}
else {
    Write-Host "Step 4: Uploading secrets to Azure Key Vault..." -ForegroundColor Cyan

    # Check for Az modules
    $azAccountsInstalled = Get-Module -Name 'Az.Accounts' -ListAvailable
    $azKeyVaultInstalled = Get-Module -Name 'Az.KeyVault' -ListAvailable

    if (-not $azAccountsInstalled -or -not $azKeyVaultInstalled) {
        Write-Host "  [WARN] Az modules not installed. Installing..." -ForegroundColor Yellow
        Install-Module -Name 'Az.Accounts' -Force -AllowClobber -Scope CurrentUser
        Install-Module -Name 'Az.KeyVault' -Force -AllowClobber -Scope CurrentUser
    }

    Import-Module Az.Accounts -Force
    Import-Module Az.KeyVault -Force

    # Connect to Azure with Key Vault scope
    Write-Host "  Connecting to Azure (Key Vault scope)..." -ForegroundColor DarkGray

    $connectParams = @{
        ErrorAction = 'Stop'
    }

    if ($SubscriptionId) {
        $connectParams['Subscription'] = $SubscriptionId
    }

    # Always reconnect with Key Vault scope to ensure proper token
    try {
        Connect-AzAccount @connectParams -AuthScope AzureKeyVaultServiceEndpointResourceId | Out-Null
    }
    catch {
        # If interactive auth fails, try device code
        Write-Host "  Trying device code authentication..." -ForegroundColor DarkGray
        Connect-AzAccount @connectParams -AuthScope AzureKeyVaultServiceEndpointResourceId -DeviceCode | Out-Null
    }

    Write-Host "  [OK] Connected to Azure" -ForegroundColor Green

    # Upload certificate secret
    Write-Host "  Uploading certificate to Key Vault..." -ForegroundColor DarkGray
    $certSecretValue = ConvertTo-SecureString -String $base64Pfx -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'AutopilotOOBE-Cert' -SecretValue $certSecretValue | Out-Null
    Write-Host "  [OK] Secret 'AutopilotOOBE-Cert' created" -ForegroundColor Green

    # Upload password secret
    Write-Host "  Uploading password to Key Vault..." -ForegroundColor DarkGray
    $pwdSecretValue = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'AutopilotOOBE-Cert-Password' -SecretValue $pwdSecretValue | Out-Null
    Write-Host "  [OK] Secret 'AutopilotOOBE-Cert-Password' created" -ForegroundColor Green
}

# ============================================================================
# STEP 5: Upload to App Registration
# ============================================================================
Write-Host ""
if ($SkipAppRegistration) {
    Write-Host "Step 5: Skipping App Registration upload (manual upload required)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Manual steps:" -ForegroundColor White
    Write-Host "  1. Go to Azure Portal > Entra ID > App registrations" -ForegroundColor DarkGray
    Write-Host "  2. Find app with Client ID: $ClientId" -ForegroundColor DarkGray
    Write-Host "  3. Go to Certificates & secrets > Certificates > Upload certificate" -ForegroundColor DarkGray
    Write-Host "  4. Upload: $cerPath" -ForegroundColor DarkGray
}
else {
    Write-Host "Step 5: Uploading certificate to App Registration..." -ForegroundColor Cyan

    # Check for Microsoft.Graph module
    $graphInstalled = Get-Module -Name 'Microsoft.Graph.Applications' -ListAvailable

    if (-not $graphInstalled) {
        Write-Host "  [WARN] Microsoft.Graph.Applications not installed. Installing..." -ForegroundColor Yellow
        Install-Module -Name 'Microsoft.Graph.Applications' -Force -AllowClobber -Scope CurrentUser
    }

    Import-Module Microsoft.Graph.Applications -Force

    # Connect to Graph
    Write-Host "  Connecting to Microsoft Graph..." -ForegroundColor DarkGray

    try {
        Connect-MgGraph -TenantId $TenantId -Scopes 'Application.ReadWrite.All' -NoWelcome -ErrorAction Stop

        # Get the app registration
        $app = Get-MgApplication -Filter "appId eq '$ClientId'" -ErrorAction Stop

        if (-not $app) {
            throw "App registration not found with Client ID: $ClientId"
        }

        # Read certificate and create key credential
        $cerBytes = [System.IO.File]::ReadAllBytes($cerPath)
        $cerBase64 = [System.Convert]::ToBase64String($cerBytes)

        $keyCredential = @{
            Type        = "AsymmetricX509Cert"
            Usage       = "Verify"
            Key         = $cerBytes
            DisplayName = $CertificateName
        }

        # Add the certificate
        Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCredential) -ErrorAction Stop

        Write-Host "  [OK] Certificate uploaded to App Registration" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not upload to App Registration: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Manual steps required:" -ForegroundColor White
        Write-Host "  1. Go to Azure Portal > Entra ID > App registrations" -ForegroundColor DarkGray
        Write-Host "  2. Find app with Client ID: $ClientId" -ForegroundColor DarkGray
        Write-Host "  3. Go to Certificates & secrets > Certificates > Upload certificate" -ForegroundColor DarkGray
        Write-Host "  4. Upload: $cerPath" -ForegroundColor DarkGray
    }
}

# ============================================================================
# STEP 6: Cleanup
# ============================================================================
Write-Host ""
if ($CleanupFiles -and -not $SkipKeyVaultUpload) {
    Write-Host "Step 6: Cleaning up local files..." -ForegroundColor Cyan

    # Remove from certificate store
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue

    # Remove exported files
    Remove-Item -Path $cerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $pfxPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $base64Path -Force -ErrorAction SilentlyContinue

    Write-Host "  [OK] Local certificate files removed" -ForegroundColor Green
}
elseif (-not $CleanupFiles) {
    Write-Host "Step 6: Local files preserved (use -CleanupFiles to remove)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Files created:" -ForegroundColor White
    Write-Host "  - $cerPath (upload to App Registration)" -ForegroundColor DarkGray
    Write-Host "  - $pfxPath (keep secure or delete)" -ForegroundColor DarkGray
    Write-Host "  - $base64Path (delete after Key Vault upload)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [!] Remember to delete these files after setup is complete!" -ForegroundColor Yellow
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Certificate Details:" -ForegroundColor Yellow
Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor White
Write-Host "  Expires:    $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
Write-Host ""

if ($SkipKeyVaultUpload -or $SkipAppRegistration) {
    Write-Host "Remaining Manual Steps:" -ForegroundColor Yellow
    if ($SkipKeyVaultUpload) {
        Write-Host "  [ ] Upload secrets to Key Vault" -ForegroundColor White
    }
    if ($SkipAppRegistration) {
        Write-Host "  [ ] Upload certificate to App Registration" -ForegroundColor White
    }
    Write-Host ""
}

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test the configuration:" -ForegroundColor White
Write-Host "     cd $(Split-Path $scriptRoot -Parent)" -ForegroundColor DarkGray
Write-Host "     Import-Module .\src\Autopilot.psd1 -Force" -ForegroundColor DarkGray
Write-Host "     Test-AutopilotPrerequisites" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2. Run a deployment:" -ForegroundColor White
Write-Host "     Start-AutopilotDeployment" -ForegroundColor DarkGray
Write-Host ""
