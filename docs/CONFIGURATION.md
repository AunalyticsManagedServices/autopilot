# Configuration Guide

## Overview

The Autopilot module uses a PowerShell Data File (`.psd1`) for configuration. This approach provides:

- **Type Safety**: PowerShell validates the data structure
- **Security**: Secrets stay in Azure Key Vault, not in config files
- **Flexibility**: Easy to customize per environment

## Quick Start

The configuration file is included at `config/autopilot.config.psd1` with Aunalytics defaults.

1. Update the Key Vault name (first time only):
   ```powershell
   notepad config\autopilot.config.psd1
   # Update: KeyVault.Name = 'your-actual-keyvault-name'
   ```

2. Test the configuration:
   ```powershell
   .\scripts\Test-LocalDeployment.ps1
   ```

## Configuration File Location

The module searches for configuration in this order:

1. Explicit path via `-ConfigPath` parameter
2. `$env:AUTOPILOT_CONFIG_PATH` environment variable
3. `config/autopilot.config.psd1` relative to module root

## Configuration Reference

### Key Vault Settings

```powershell
KeyVault = @{
    # Name of the Azure Key Vault (REQUIRED)
    Name = 'your-keyvault-name'

    # Name of the secret containing the Base64-encoded PFX (REQUIRED)
    CertSecretName = 'AutopilotOOBE-Cert'

    # Name of the secret containing the PFX password
    # Default: '{CertSecretName}-Password'
    PasswordSecretName = 'AutopilotOOBE-Cert-Password'

    # Azure subscription ID (optional - uses default if not specified)
    SubscriptionId = '00000000-0000-0000-0000-000000000000'
}
```

### App Registration

```powershell
# Entra ID tenant ID (REQUIRED)
TenantId = '00000000-0000-0000-0000-000000000000'

# App registration client ID (REQUIRED)
ClientId = '00000000-0000-0000-0000-000000000000'
```

### Deployment Settings

```powershell
# Title shown in AutopilotOOBE window
Title = 'Autopilot Registration'

# Example username shown in UI
AssignedUserExample = 'username@contoso.com'

# Example computer name pattern
AssignedComputerNameExample = 'PC####'

# Default group for device assignment
DefaultGroup = 'Autopilot-Devices'

# Available groups in dropdown
GroupOptions = @(
    'Autopilot-Devices',
    'Autopilot-Kiosk',
    'Autopilot-Shared'
)

# Default group tag for Autopilot profile
DefaultGroupTag = 'Standard'

# Available group tags in dropdown
GroupTagOptions = @(
    'Standard',
    'Kiosk',
    'Shared'
)
```

### Regional Settings

```powershell
# Windows time zone ID
TimeZone = 'Eastern Standard Time'
```

Common time zone IDs:
- `Eastern Standard Time`
- `Central Standard Time`
- `Mountain Standard Time`
- `Pacific Standard Time`
- `UTC`

### Behavior Settings

```powershell
# Remove existing device records before registration
CleanupExistingDevices = $true

# Skip Entra group validation
SkipGroupValidation = $false

# Action after registration: 'Restart', 'Shutdown', 'Sysprep', 'None'
PostAction = 'Restart'

# What to run after registration
Run = 'WindowsSettings'

# Auto-assign device to Autopilot
Assign = $true

# Documentation URL shown in UI
DocsUrl = 'https://autopilotoobe.osdeploy.com/'
```

### Retry Policy

```powershell
RetryPolicy = @{
    # Maximum retry attempts (1-10)
    MaxAttempts = 3

    # Initial delay in milliseconds (100-60000)
    InitialDelayMs = 1000

    # Backoff multiplier (1.0-5.0)
    BackoffMultiplier = 2.0
}
```

With these defaults:
- Attempt 1: Immediate
- Attempt 2: 1 second delay
- Attempt 3: 2 second delay

### Logging Settings

```powershell
Logging = @{
    # Enable JSON log files
    EnableJsonLog = $true

    # Minimum log level: 'Debug', 'Info', 'Warning', 'Error'
    Level = 'Info'

    # Custom log path (optional)
    # Default: $env:TEMP\Autopilot-{date}.json
    Path = 'C:\Logs\Autopilot.json'
}
```

### Propagation Delays

```powershell
PropagationDelays = @{
    # Seconds to wait after Entra cleanup
    EntraCleanup = 15

    # Seconds to wait after Intune cleanup
    IntuneCleanup = 10

    # Seconds to wait after Autopilot cleanup
    AutopilotCleanup = 10
}
```

## Complete Example

```powershell
@{
    # Key Vault
    KeyVault = @{
        Name = 'contoso-autopilot-kv'
        CertSecretName = 'AutopilotOOBE-Cert'
    }

    # App Registration
    TenantId = '12345678-1234-1234-1234-123456789012'
    ClientId = 'abcdefgh-1234-1234-1234-123456789012'

    # Deployment
    Title = 'Contoso Autopilot Registration'
    AssignedUserExample = 'user@contoso.com'
    AssignedComputerNameExample = 'CON-####'
    DefaultGroup = 'Autopilot-Standard'
    GroupOptions = @('Autopilot-Standard', 'Autopilot-Executive', 'Autopilot-Lab')
    DefaultGroupTag = 'Standard'
    GroupTagOptions = @('Standard', 'Executive', 'Lab')

    # Regional
    TimeZone = 'Pacific Standard Time'

    # Behavior
    CleanupExistingDevices = $true
    SkipGroupValidation = $false
    PostAction = 'Restart'
    Run = 'WindowsSettings'
    Assign = $true
    DocsUrl = 'https://wiki.contoso.com/autopilot'

    # Retry
    RetryPolicy = @{
        MaxAttempts = 3
        InitialDelayMs = 1000
        BackoffMultiplier = 2.0
    }

    # Logging
    Logging = @{
        EnableJsonLog = $true
        Level = 'Info'
    }

    # Delays
    PropagationDelays = @{
        EntraCleanup = 15
        IntuneCleanup = 10
        AutopilotCleanup = 10
    }
}
```

## Azure Key Vault Setup

### Automated Setup (Recommended)

Use the provided setup script to configure everything automatically:

```powershell
# Interactive mode
.\scripts\Setup-CertificateAuth.ps1

# Fully automated
.\scripts\Setup-CertificateAuth.ps1 -CertificatePassword "YourSecurePass123!" -CleanupFiles
```

The script will:
1. Generate a self-signed certificate
2. Upload the public key to your App Registration
3. Store the Base64 PFX and password in Key Vault
4. Clean up local files (with `-CleanupFiles`)

### Manual Setup

If you prefer manual setup:

#### Step 1: Generate Certificate

```powershell
# Create certificate
$cert = New-SelfSignedCertificate `
    -Subject "CN=AutopilotOOBE-Auth" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

# Export public key (.cer) for App Registration
Export-Certificate -Cert $cert -FilePath "$env:USERPROFILE\Desktop\AutopilotOOBE-Auth.cer"

# Export private key (.pfx)
$password = ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$env:USERPROFILE\Desktop\AutopilotOOBE-Auth.pfx" -Password $password

# Convert to Base64 for Key Vault
$pfxBytes = [System.IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\AutopilotOOBE-Auth.pfx")
$base64 = [System.Convert]::ToBase64String($pfxBytes)
$base64 | Out-File "$env:USERPROFILE\Desktop\AutopilotOOBE-Auth-Base64.txt" -NoNewline
```

#### Step 2: Upload to App Registration

1. Go to **Azure Portal** → **Entra ID** → **App registrations**
2. Select your app registration
3. Go to **Certificates & secrets** → **Certificates**
4. Click **Upload certificate** and select the `.cer` file

#### Step 3: Store in Key Vault

```powershell
# Using Azure CLI
az login
az account set --subscription "your-subscription-id"

# Store certificate (Base64 PFX)
$base64 = Get-Content "$env:USERPROFILE\Desktop\AutopilotOOBE-Auth-Base64.txt" -Raw
az keyvault secret set --vault-name "IITScriptKeyVault" --name "AutopilotOOBE-Cert" --value $base64

# Store password
az keyvault secret set --vault-name "IITScriptKeyVault" --name "AutopilotOOBE-Cert-Password" --value "YourPassword"
```

#### Step 4: Clean Up

Delete local certificate files after Key Vault upload:
```powershell
Remove-Item "$env:USERPROFILE\Desktop\AutopilotOOBE-Auth.*" -Force
```

### Key Vault Access Policy

Ensure users who run the deployment have access to Key Vault secrets:

```powershell
# Grant access to a user
az keyvault set-policy --name "IITScriptKeyVault" --upn "user@aunalytics.com" --secret-permissions get list

# Grant access to a group
az keyvault set-policy --name "IITScriptKeyVault" --object-id "group-object-id" --secret-permissions get list
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `AUTOPILOT_CONFIG_PATH` | Path to configuration file |

## Validation

Validate your configuration before deployment:

```powershell
# Full prerequisite check
Test-AutopilotPrerequisites

# Just check config loading
$config = Import-PowerShellDataFile .\config\autopilot.config.psd1
```

## Security Best Practices

1. **Config file is safe to commit** - contains only identifiers, not secrets
2. All secrets (certificates, passwords) are stored in Azure Key Vault
3. Use separate Key Vaults for dev/test/prod
4. Rotate certificates before expiry (check with `Test-AutopilotPrerequisites`)
5. Use least-privilege access policies for Key Vault
6. For local overrides, use `*.local.psd1` files (gitignored)
