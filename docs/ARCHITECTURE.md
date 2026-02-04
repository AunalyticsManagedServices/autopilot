# Autopilot Module Architecture

## Overview

The Autopilot module is a comprehensive PowerShell framework for Windows Autopilot OOBE deployment. It provides:

- **Azure Key Vault Integration**: Secure credential management without hardcoded secrets
- **Retry Logic**: Exponential backoff for handling transient failures
- **Structured Logging**: JSON logs for troubleshooting and analysis
- **State Machine**: Resumable deployments with checkpoint tracking
- **Modular Design**: Testable, maintainable code organization

## Directory Structure

```
Autopilot/
├── src/
│   ├── Autopilot.psd1              # Module manifest
│   ├── Autopilot.psm1              # Root module
│   │
│   ├── Public/                      # Exported functions
│   │   ├── Start-AutopilotDeployment.ps1
│   │   ├── Test-AutopilotPrerequisites.ps1
│   │   └── Get-AutopilotStatus.ps1
│   │
│   ├── Private/                     # Internal functions
│   │   ├── Authentication/
│   │   ├── DeviceCleanup/
│   │   ├── Enrollment/
│   │   ├── Validation/
│   │   ├── Configuration/
│   │   └── Utilities/
│   │
│   └── Classes/                     # PowerShell classes
│       ├── AutopilotConfig.ps1
│       ├── DeploymentState.ps1
│       └── DeploymentResult.ps1
│
├── config/
│   ├── autopilot.config.psd1        # Actual config (gitignored)
│   └── autopilot.config.sample.psd1 # Sample config (committed)
│
├── tests/
│   ├── Unit/
│   └── Mocks/
│
├── scripts/
│   ├── Deploy-FromOOBE.ps1
│   └── Test-LocalDeployment.ps1
│
└── docs/
    ├── ARCHITECTURE.md
    ├── CONFIGURATION.md
    └── TROUBLESHOOTING.md
```

## Component Overview

### Public Functions

| Function | Description |
|----------|-------------|
| `Start-AutopilotDeployment` | Main entry point - orchestrates the complete deployment |
| `Test-AutopilotPrerequisites` | Validates all prerequisites without deploying |
| `Get-AutopilotStatus` | Returns current deployment status and diagnostics |

### Deployment Flow

```
┌────────────────────────────────────────────────────────────────┐
│                    Start-AutopilotDeployment                    │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Load Configuration                                          │
│     └─ Get-AutopilotConfig → Merge-ConfigWithDefaults          │
│        └─ Test-ConfigValidation                                │
│                                                                 │
│  2. Pre-Flight Checks                                          │
│     ├─ Test-NetworkConnectivity                                │
│     └─ Test-RequiredModules (with auto-install)                │
│                                                                 │
│  3. Azure Authentication                                        │
│     └─ Connect-AzureKeyVault (device code flow)                │
│                                                                 │
│  4. Certificate Retrieval                                       │
│     └─ Get-CertificateFromKeyVault                             │
│                                                                 │
│  5. Graph Authentication                                        │
│     └─ Connect-GraphWithCertificate                            │
│                                                                 │
│  6. Device Cleanup (optional)                                   │
│     ├─ Remove-EntraDeviceRecords                               │
│     ├─ Remove-IntuneDeviceRecords                              │
│     └─ Remove-AutopilotRegistration                            │
│                                                                 │
│  7. Group Validation (optional)                                 │
│     └─ Test-EntraGroupExists                                   │
│                                                                 │
│  8. Autopilot Registration                                      │
│     ├─ Set-TimeZone                                            │
│     └─ Register-AutopilotDevice (launches AutopilotOOBE)       │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### State Machine

The deployment uses a state machine (`DeploymentState` class) to enable:

- **Resumable Deployments**: If deployment fails, it can resume from the last checkpoint
- **Duplicate Prevention**: Tracks which devices were already cleaned up
- **Debugging**: Provides clear status of what phases completed

```powershell
enum DeploymentPhase {
    NotStarted
    PreFlightChecks
    ModuleInstallation
    AzureAuthentication
    KeyVaultAccess
    GraphAuthentication
    DeviceCleanup
    EntraCleanup
    IntuneCleanup
    AutopilotCleanup
    GroupValidation
    DeviceRegistration
    OOBELaunch
    Completed
    Failed
}
```

State is persisted to `$env:TEMP\Autopilot-DeploymentState.xml` and automatically loaded on subsequent runs.

### Retry Logic

All Graph API operations are wrapped with `Invoke-WithRetry`:

```powershell
$devices = Invoke-WithRetry -OperationName 'Get Autopilot devices' -ScriptBlock {
    Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "..."
}
```

Features:
- Configurable max attempts (default: 3)
- Exponential backoff (delay doubles each retry)
- Smart error detection (only retries transient errors)
- Recognizes: timeout, network, HTTP 429/503/504, throttling

### Caching

Device identifiers are cached at the module scope to avoid repeated WMI queries:

```powershell
# First call queries WMI
$deviceInfo = Get-DeviceIdentifiers

# Subsequent calls return cached data
$serial = Get-DeviceSerialNumber  # Uses cache
```

## Security Design

### Credential Flow

```
┌─────────────────────────────────────────────────────┐
│  Configuration File (config/autopilot.config.psd1) │
│  Contains: TenantId, ClientId, KeyVault name       │
│  Does NOT contain: Secrets, certificates, passwords │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  Azure Key Vault                                    │
│  ├─ AutopilotOOBE-Cert (Base64 PFX)                │
│  └─ AutopilotOOBE-Cert-Password (PFX password)     │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  Microsoft Graph (Certificate Auth)                 │
│  App-only authentication with no user interaction   │
└─────────────────────────────────────────────────────┘
```

### Security Features

1. **No Hardcoded Credentials**: All secrets stored in Azure Key Vault
2. **Device Code Flow**: Azure authentication works during OOBE
3. **Certificate-Based Auth**: No passwords for Graph API
4. **Memory Cleanup**: Certificates cleared from memory after use
5. **Audit Trail**: Key Vault provides access logging

## Testing

### Unit Tests

Located in `tests/Unit/`:
- `Configuration.Tests.ps1` - Config validation
- `Utilities.Tests.ps1` - Retry logic, logging
- `Authentication.Tests.ps1` - Graph connection testing
- `DeviceCleanup.Tests.ps1` - Device identifier caching

### Running Tests

```powershell
# Install Pester if needed
Install-Module Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester -Path .\tests\Unit -Output Detailed

# Run specific test file
Invoke-Pester -Path .\tests\Unit\Configuration.Tests.ps1 -Output Detailed
```

## Dependencies

### Required Modules

| Module | Version | Purpose |
|--------|---------|---------|
| Microsoft.Graph.Authentication | ≥2.0.0 | Graph API auth |
| Microsoft.Graph.Groups | ≥2.0.0 | Group validation |
| Microsoft.Graph.Identity.DirectoryManagement | ≥2.0.0 | Device management |
| Microsoft.Graph.DeviceManagement.Enrollment | ≥2.0.0 | Autopilot operations |
| Microsoft.Graph.DeviceManagement | ≥2.0.0 | Intune operations |
| Az.Accounts | ≥2.0.0 | Azure authentication |
| Az.KeyVault | ≥4.0.0 | Key Vault access |
| AutopilotOOBE | ≥24.1.29 | OOBE interface |
| PSWriteColor | any | Colored console output |

## Configuration

See [CONFIGURATION.md](CONFIGURATION.md) for detailed configuration documentation.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.
