# Windows Autopilot OOBE Deployment Module

Automated Windows Autopilot device registration module designed for zero-touch deployment during OOBE (Out-of-Box Experience).

## Version 6.0 - Complete Redesign

This version is a complete architectural redesign featuring:

- **Azure Key Vault Integration**: Secure credential management (no hardcoded secrets)
- **Retry Logic**: Exponential backoff for handling transient failures
- **Structured Logging**: JSON logs for troubleshooting and analysis
- **State Machine**: Resumable deployments with checkpoint tracking
- **Comprehensive Testing**: Pester unit test suite

## Features

- **Zero-Prompt Authentication**: Certificate-based authentication via Entra App Registration
- **Secure Credential Storage**: Certificates stored in Azure Key Vault
- **Duplicate Device Prevention**: Removes existing Entra, Intune, and Autopilot registrations
- **Entra Group Validation**: Validates target groups exist before deployment
- **Resilient Operations**: Automatic retry with exponential backoff
- **Resumable Deployments**: Can resume from partial failures
- **Structured Logging**: JSON logs for analysis and troubleshooting

## Prerequisites

### Azure/Entra ID Setup

1. **Entra App Registration** with the following API permissions (Application type):
   - `DeviceManagementServiceConfig.ReadWrite.All`
   - `DeviceManagementManagedDevices.ReadWrite.All`
   - `Device.ReadWrite.All`
   - `Directory.Read.All`
   - `Group.Read.All`

2. **Certificate Authentication**:
   - Upload the public key (`.cer`) to the App Registration
   - Store the PFX (Base64-encoded) and password in Azure Key Vault

3. **Azure Key Vault**:
   - Create a Key Vault in your Azure subscription
   - Store the certificate and password as secrets
   - Grant access to users who will run the deployment

### PowerShell Modules (Auto-Installed)

- Microsoft.Graph modules (v2.0.0+)
- Az.Accounts and Az.KeyVault (v2.0.0+/v4.0.0+)
- AutopilotOOBE (v24.1.29+)
- PSWriteColor

## Quick Start

### 1. Setup Certificate Authentication

Run the setup script to generate a certificate and configure Key Vault:

```powershell
# Interactive mode (prompts for password)
.\scripts\Setup-CertificateAuth.ps1

# Automated mode with cleanup
.\scripts\Setup-CertificateAuth.ps1 -CertificatePassword "YourSecurePass123!" -CleanupFiles
```

The script will:
- Generate a self-signed certificate (2-year validity)
- Upload the certificate to your App Registration
- Store the certificate and password in Azure Key Vault
- Clean up local files (optional)

### 2. Test Prerequisites

```powershell
# Run from the scripts directory
.\scripts\Test-LocalDeployment.ps1
```

### 3. Deploy During OOBE

Press `Shift + F10` to open Command Prompt, then run:

```cmd
powershell -ExecutionPolicy Bypass -Command "irm https://tinyurl.com/AUAPOOBE | iex"
```

Or use the direct URL:

```cmd
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AunalyticsManagedServices/autopilot/main/scripts/Deploy-FromOOBE.ps1 | iex"
```

Or if the module is pre-staged locally:

```powershell
Import-Module C:\Autopilot\src\Autopilot.psd1
Start-AutopilotDeployment
```

## Module Commands

### Start-AutopilotDeployment

Main entry point for deployment.

```powershell
# Basic deployment
Start-AutopilotDeployment

# With custom config path
Start-AutopilotDeployment -ConfigPath 'C:\Config\autopilot.config.psd1'

# Skip device cleanup (not recommended)
Start-AutopilotDeployment -SkipCleanup

# Force fresh start (ignore saved state)
Start-AutopilotDeployment -Force
```

### Test-AutopilotPrerequisites

Validates all prerequisites without deploying.

```powershell
# Check prerequisites
Test-AutopilotPrerequisites

# Auto-install missing modules
Test-AutopilotPrerequisites -AutoFix
```

### Get-AutopilotStatus

Returns current deployment status and diagnostics.

```powershell
Get-AutopilotStatus
```

## Configuration

Configuration is stored in `config/autopilot.config.psd1`. See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for full reference.

Key settings:

```powershell
@{
    # Azure Key Vault
    KeyVault = @{
        Name = 'your-keyvault-name'
        CertSecretName = 'AutopilotOOBE-Cert'
    }

    # App Registration
    TenantId = 'your-tenant-id'
    ClientId = 'your-client-id'

    # Deployment settings
    DefaultGroup = 'Autopilot-Devices'
    GroupOptions = @('Autopilot-Devices', 'Autopilot-Kiosk')
    TimeZone = 'Eastern Standard Time'
    PostAction = 'Restart'
}
```

## Directory Structure

```
Autopilot/
├── src/                    # Module source code
│   ├── Autopilot.psd1      # Module manifest
│   ├── Autopilot.psm1      # Root module
│   ├── Public/             # Exported functions
│   ├── Private/            # Internal functions
│   └── Classes/            # PowerShell classes
├── config/                 # Configuration files
├── scripts/                # Utility scripts
├── tests/                  # Pester tests
└── docs/                   # Documentation
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

Logs are stored in:
- Transcript: `$env:TEMP\AutopilotOOBE_*.log`
- JSON structured: `$env:TEMP\Autopilot-*.json`

## Testing

```powershell
# Install Pester if needed
Install-Module Pester -Force -SkipPublisherCheck

# Run unit tests
Invoke-Pester -Path .\tests\Unit -Output Detailed
```

## Security Notes

- Configuration file is safe to commit (contains only identifiers, not secrets)
- Certificates and passwords are stored in Azure Key Vault
- Use least-privilege access policies for Key Vault
- Rotate certificates before expiration

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration](docs/CONFIGURATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Version History

| Version | Description |
|---------|-------------|
| 6.0 | Complete redesign with Key Vault, retry logic, state machine |
| 5.1 | Added comprehensive device cleanup |
| 5.0 | Certificate-based authentication |
| 4.0 | Azure Key Vault integration (original) |
| 3.x | Pre-flight checks, group validation |

## License

Internal use only - Aunalytics
