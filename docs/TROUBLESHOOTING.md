# Troubleshooting Guide

## Common Issues

### Certificate/Key Vault Issues

#### Error: "Certificate secret not found in Key Vault"

**Cause**: The secret name in config doesn't match what's in Key Vault, or secrets haven't been created.

**Solution**:
1. Run the setup script to configure everything:
   ```powershell
   .\scripts\Setup-CertificateAuth.ps1
   ```
2. Or verify manually:
   ```powershell
   # Check Key Vault access
   Connect-AzAccount
   Get-AzKeyVaultSecret -VaultName 'IITScriptKeyVault' -Name 'AutopilotOOBE-Cert'
   Get-AzKeyVaultSecret -VaultName 'IITScriptKeyVault' -Name 'AutopilotOOBE-Cert-Password'
   ```
3. Ensure secret names in config match exactly:
   ```powershell
   # In config/autopilot.config.psd1
   KeyVault = @{
       Name               = 'IITScriptKeyVault'
       CertSecretName     = 'AutopilotOOBE-Cert'      # Must match Key Vault
       PasswordSecretName = 'AutopilotOOBE-Cert-Password'  # Must match Key Vault
   }
   ```

#### Error: "Failed to create certificate from Key Vault secrets"

**Cause**: The Base64 encoding is incorrect or the password is wrong.

**Solution**:
1. Re-export the PFX and encode properly:
   ```powershell
   $pfxBytes = [System.IO.File]::ReadAllBytes('cert.pfx')
   $base64 = [System.Convert]::ToBase64String($pfxBytes)
   ```
2. Verify the password secret matches what was used during export
3. Test locally:
   ```powershell
   $pfxBytes = [Convert]::FromBase64String($base64)
   $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxBytes, 'password')
   ```

#### Error: "Certificate has expired"

**Cause**: The deployment certificate has passed its expiration date.

**Solution**:
Run the setup script to generate and deploy a new certificate:
```powershell
.\scripts\Setup-CertificateAuth.ps1 -CleanupFiles
```

This will:
1. Generate a new 2-year certificate
2. Upload to Key Vault (overwrites existing secrets)
3. Upload to App Registration
4. Clean up local files

#### Certificate expiring soon warning

**Cause**: Certificate expires within 30 days.

**Solution**:
Proactively renew before expiration:
```powershell
# Check current expiration
Test-AutopilotPrerequisites

# Renew if expiring soon
.\scripts\Setup-CertificateAuth.ps1 -CleanupFiles
```

Set a calendar reminder to renew certificates before the 2-year expiration.

### Authentication Issues

#### Error: "Azure authentication failed"

**Cause**: Device code flow didn't complete or timed out.

**Solution**:
1. Ensure the OOBE device has internet access
2. Complete the device code flow in a browser
3. Try again - network connectivity during OOBE can be intermittent

#### Error: "Failed to connect to Microsoft Graph"

**Cause**: Certificate not authorized for the app registration.

**Solution**:
1. Verify the certificate thumbprint is registered in the App Registration
2. Ensure admin consent was granted for required permissions
3. Check the App Registration has these API permissions:
   - `DeviceManagementManagedDevices.ReadWrite.All`
   - `DeviceManagementServiceConfig.ReadWrite.All`
   - `Directory.Read.All`
   - `Group.Read.All`

### Network Issues

#### Error: "Network connectivity check failed"

**Cause**: Device can't reach required Microsoft endpoints.

**Solution**:
1. Ensure the device is connected to a network with internet access
2. Check firewall rules allow HTTPS to:
   - `graph.microsoft.com`
   - `login.microsoftonline.com`
   - `www.powershellgallery.com`
3. If behind a proxy, configure proxy settings

#### Error: "HTTP 429 Too Many Requests"

**Cause**: Microsoft Graph API throttling.

**Solution**:
- The module automatically retries with exponential backoff
- If persistent, increase retry delays in config:
  ```powershell
  RetryPolicy = @{
      MaxAttempts = 5
      InitialDelayMs = 2000
      BackoffMultiplier = 3.0
  }
  ```

### Device Cleanup Issues

#### Error: "Device already enrolled" (0x8018000a)

**Cause**: Existing device records weren't fully cleaned up.

**Solution**:
1. Ensure `CleanupExistingDevices = $true` in config
2. Increase propagation delays:
   ```powershell
   PropagationDelays = @{
       EntraCleanup = 30
       IntuneCleanup = 20
       AutopilotCleanup = 20
   }
   ```
3. Wait a few minutes and try again

#### Device records not being removed

**Cause**: App Registration lacks delete permissions.

**Solution**:
Add these permissions to the App Registration:
- `Device.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`

### Configuration Issues

#### Error: "Configuration file not found"

**Cause**: No config file at expected locations.

**Solution**:
1. Create `config/autopilot.config.psd1` from the sample
2. Or set `$env:AUTOPILOT_CONFIG_PATH`
3. Or use `-ConfigPath` parameter

#### Error: "Configuration validation failed"

**Cause**: Invalid values in configuration file.

**Solution**:
1. Check the error message for specific fields
2. Verify GUIDs are in correct format
3. Check Key Vault name follows Azure naming rules
4. Validate time zone ID is valid Windows time zone

### Module Issues

#### Error: "Module not loaded"

**Cause**: Required modules not installed or import failed.

**Solution**:
```powershell
# Re-run prerequisites with auto-install
Test-AutopilotPrerequisites -AutoFix
```

#### PowerShell Gallery unreachable

**Cause**: Network restrictions or PS Gallery outage.

**Solution**:
1. Check `www.powershellgallery.com` is accessible
2. Manually install modules:
   ```powershell
   Save-Module -Name Microsoft.Graph.Authentication -Path C:\Modules
   # Copy to target machine
   ```

## Diagnostic Commands

### Check Current Status

```powershell
# Full status report
Get-AutopilotStatus

# Prerequisites check
Test-AutopilotPrerequisites
```

### View Logs

```powershell
# Transcript logs
Get-ChildItem $env:TEMP -Filter 'AutopilotOOBE*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# JSON structured logs
Get-ChildItem $env:TEMP -Filter 'Autopilot-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# Read latest log
$latestLog = Get-ChildItem $env:TEMP -Filter 'AutopilotOOBE*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latestLog.FullName
```

### Check Graph Connection

```powershell
# Current context
Get-MgContext

# Test API access
Get-MgDevice -Top 1
```

### Check Azure Connection

```powershell
# Current context
Get-AzContext

# List Key Vault secrets
Get-AzKeyVaultSecret -VaultName 'your-vault'
```

### Check Device State

```powershell
# Deployment state file
$statePath = Join-Path $env:TEMP 'Autopilot-DeploymentState.xml'
if (Test-Path $statePath) {
    Import-Clixml $statePath
}
```

### Force Fresh Start

```powershell
# Remove state file and start fresh
Remove-Item "$env:TEMP\Autopilot-DeploymentState.xml" -Force -ErrorAction SilentlyContinue
Start-AutopilotDeployment -Force
```

## Log Analysis

### JSON Log Format

```json
{
  "Timestamp": "2024-01-15T10:30:45.123Z",
  "Level": "Info",
  "Phase": "DeviceCleanup",
  "Message": "Removed Entra device: WAU1234",
  "Device": "ABC123456",
  "Data": {
    "DeviceId": "device-id-here",
    "DisplayName": "WAU1234"
  }
}
```

### Parse JSON Logs

```powershell
$logPath = Get-ChildItem $env:TEMP -Filter 'Autopilot-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $logPath.FullName | ConvertFrom-Json | Where-Object Level -eq 'Error'
```

## Getting Help

### Collect Diagnostics

Before requesting support, gather:

1. **Log files** from `$env:TEMP`:
   - `AutopilotOOBE_*.log` (transcript)
   - `Autopilot-*.json` (structured log)

2. **Status output**:
   ```powershell
   Get-AutopilotStatus | ConvertTo-Json -Depth 5 | Out-File diagnostics.json
   ```

3. **Configuration** (without secrets):
   ```powershell
   $config = Import-PowerShellDataFile config\autopilot.config.psd1
   $config.Remove('KeyVault')  # Remove sensitive info
   $config | ConvertTo-Json -Depth 5
   ```

4. **Error message** - exact text and any error codes

### Common Error Codes

| Code | Meaning | Solution |
|------|---------|----------|
| 0x8018000a | Device already enrolled | Run device cleanup, increase delays |
| 0x80070005 | Access denied | Check permissions, run as admin |
| 0x80072EE7 | Cannot connect | Check network, DNS, firewall |
| AADSTS700016 | App not found | Verify ClientId in config |
| AADSTS7000215 | Invalid secret | Certificate issue, check Key Vault |
