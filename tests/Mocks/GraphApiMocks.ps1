<#
.SYNOPSIS
    Mock definitions for Microsoft Graph API cmdlets.

.DESCRIPTION
    Provides reusable mock configurations for Pester tests involving
    Microsoft Graph API operations.
#>

function Initialize-GraphMocks {
    <#
    .SYNOPSIS
        Sets up standard Graph API mocks for testing.
    #>
    [CmdletBinding()]
    param(
        [switch]$Connected,
        [switch]$WithDevices,
        [switch]$WithGroups
    )

    # Graph connection mock
    if ($Connected) {
        Mock Get-MgContext {
            return [PSCustomObject]@{
                TenantId = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
                ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
                Scopes   = @('.default')
                AuthType = 'AppOnly'
            }
        }

        Mock Connect-MgGraph { return $true }
    }
    else {
        Mock Get-MgContext { return $null }
    }

    # Device mocks
    if ($WithDevices) {
        Mock Get-MgDevice {
            param($Filter)
            if ($Filter -match "displayName eq '(.+)'") {
                return @(
                    [PSCustomObject]@{
                        Id          = 'device-id-123'
                        DisplayName = $Matches[1]
                        TrustType   = 'AzureAd'
                    }
                )
            }
            return @()
        }

        Mock Remove-MgDevice { return $true }

        Mock Get-MgDeviceManagementManagedDevice {
            param($Filter)
            if ($Filter -match "serialNumber eq '(.+)'") {
                return @(
                    [PSCustomObject]@{
                        Id           = 'managed-device-123'
                        DeviceName   = 'TestDevice'
                        SerialNumber = $Matches[1]
                    }
                )
            }
            return @()
        }

        Mock Remove-MgDeviceManagementManagedDevice { return $true }

        Mock Get-MgDeviceManagementWindowsAutopilotDeviceIdentity {
            param($Filter)
            if ($Filter -match "contains\(serialNumber,'(.+)'\)") {
                return @(
                    [PSCustomObject]@{
                        Id           = 'autopilot-id-123'
                        SerialNumber = $Matches[1]
                        GroupTag     = 'Enterprise'
                    }
                )
            }
            return @()
        }

        Mock Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity { return $true }
    }

    # Group mocks
    if ($WithGroups) {
        Mock Get-MgGroup {
            param($Filter)
            if ($Filter -match "displayName eq '(.+)'") {
                $groupName = $Matches[1]
                # Return group for known groups
                if ($groupName -match 'AzPC|Autopilot') {
                    return [PSCustomObject]@{
                        Id          = "group-id-$($groupName.GetHashCode())"
                        DisplayName = $groupName
                    }
                }
            }
            return $null
        }
    }
}

function Initialize-KeyVaultMocks {
    <#
    .SYNOPSIS
        Sets up Azure Key Vault mocks for testing.
    #>
    [CmdletBinding()]
    param(
        [switch]$WithCertificate
    )

    Mock Get-AzContext {
        return [PSCustomObject]@{
            Account      = [PSCustomObject]@{ Id = 'test@example.com' }
            Subscription = [PSCustomObject]@{ Name = 'Test Subscription'; Id = '12345678-1234-1234-1234-123456789012' }
            Tenant       = [PSCustomObject]@{ Id = '34996142-c2c2-49f6-a30d-ccf73f568c9c' }
        }
    }

    Mock Connect-AzAccount { return $true }
    Mock Set-AzContext { return $true }

    if ($WithCertificate) {
        # Base64-encoded minimal test certificate
        $testCertBase64 = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA'

        Mock Get-AzKeyVaultSecret {
            param($VaultName, $Name, [switch]$AsPlainText)

            if ($Name -match 'Cert$') {
                return $testCertBase64
            }
            if ($Name -match 'Password') {
                return 'TestPassword123!'
            }
            return $null
        }
    }
}

function Initialize-WmiMocks {
    <#
    .SYNOPSIS
        Sets up WMI/CIM mocks for testing.
    #>
    [CmdletBinding()]
    param(
        [string]$SerialNumber = 'TEST123456',
        [string]$Manufacturer = 'TestManufacturer',
        [string]$Model = 'TestModel'
    )

    Mock Get-CimInstance {
        param($ClassName)

        switch ($ClassName) {
            'Win32_BIOS' {
                return [PSCustomObject]@{
                    SerialNumber = $SerialNumber
                }
            }
            'Win32_ComputerSystem' {
                return [PSCustomObject]@{
                    Manufacturer = $Manufacturer
                    Model        = $Model
                }
            }
            'Win32_SystemEnclosure' {
                return [PSCustomObject]@{
                    SerialNumber = $SerialNumber
                }
            }
            default {
                return $null
            }
        }
    }
}

# Export mock functions
Export-ModuleMember -Function Initialize-GraphMocks, Initialize-KeyVaultMocks, Initialize-WmiMocks
