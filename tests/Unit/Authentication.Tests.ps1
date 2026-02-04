#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Authentication functions.
#>

BeforeAll {
    # Import the module functions directly for testing
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\src'

    # Initialize module-scoped variables
    $script:Config = @{
        RetryPolicy = @{
            MaxAttempts = 1
            InitialDelayMs = 10
            BackoffMultiplier = 1.0
        }
        Logging = @{
            EnableJsonLog = $false
            Level = 'Warning'
        }
    }
    $script:DeviceIdentifiers = $null
    $script:LogPath = $null

    # Dot-source required functions
    . "$ModuleRoot\Private\Utilities\Write-AutopilotLog.ps1"
    . "$ModuleRoot\Private\Utilities\Invoke-WithRetry.ps1"
    . "$ModuleRoot\Private\Authentication\Test-GraphConnection.ps1"
}

Describe 'Test-GraphConnection' {
    It 'should return false when not connected' {
        Mock Get-MgContext { return $null }

        $result = Test-GraphConnection

        $result | Should -Be $false
    }

    It 'should return true when connected' {
        Mock Get-MgContext {
            return @{
                TenantId = '12345678-1234-1234-1234-123456789012'
                Scopes = @('.default')
            }
        }

        $result = Test-GraphConnection

        $result | Should -Be $true
    }

    It 'should check for required scopes' {
        Mock Get-MgContext {
            return @{
                TenantId = '12345678-1234-1234-1234-123456789012'
                Scopes = @('User.Read', 'Group.Read.All')
            }
        }

        $result = Test-GraphConnection -RequiredScopes @('User.Read')

        $result | Should -Be $true
    }

    It 'should return false when missing required scopes' {
        Mock Get-MgContext {
            return @{
                TenantId = '12345678-1234-1234-1234-123456789012'
                Scopes = @('User.Read')
            }
        }

        $result = Test-GraphConnection -RequiredScopes @('Device.ReadWrite.All')

        $result | Should -Be $false
    }

    It 'should accept .default scope as satisfying all requirements' {
        Mock Get-MgContext {
            return @{
                TenantId = '12345678-1234-1234-1234-123456789012'
                Scopes = @('.default')
            }
        }

        $result = Test-GraphConnection -RequiredScopes @('Device.ReadWrite.All', 'User.Read')

        $result | Should -Be $true
    }

    It 'should handle Get-MgContext errors gracefully' {
        Mock Get-MgContext { throw "Module not loaded" }

        $result = Test-GraphConnection

        $result | Should -Be $false
    }
}

Describe 'Certificate Validation' {
    BeforeAll {
        # Create test certificate helper
        function New-TestCertificate {
            param(
                [datetime]$NotBefore = (Get-Date).AddDays(-1),
                [datetime]$NotAfter = (Get-Date).AddDays(30),
                [bool]$HasPrivateKey = $true
            )

            # Create a mock certificate object
            $cert = [PSCustomObject]@{
                Subject = 'CN=Test'
                Thumbprint = 'ABCD1234'
                NotBefore = $NotBefore
                NotAfter = $NotAfter
                HasPrivateKey = $HasPrivateKey
            }
            return $cert
        }
    }

    It 'should detect valid certificate' {
        $cert = New-TestCertificate

        $now = Get-Date
        $isValid = $cert.NotBefore -le $now -and $cert.NotAfter -ge $now -and $cert.HasPrivateKey

        $isValid | Should -Be $true
    }

    It 'should detect expired certificate' {
        $cert = New-TestCertificate -NotAfter (Get-Date).AddDays(-1)

        $now = Get-Date
        $isExpired = $cert.NotAfter -lt $now

        $isExpired | Should -Be $true
    }

    It 'should detect not-yet-valid certificate' {
        $cert = New-TestCertificate -NotBefore (Get-Date).AddDays(1)

        $now = Get-Date
        $isNotYetValid = $cert.NotBefore -gt $now

        $isNotYetValid | Should -Be $true
    }

    It 'should calculate days until expiry' {
        $expiryDate = (Get-Date).AddDays(45)
        $cert = New-TestCertificate -NotAfter $expiryDate

        $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days

        $daysUntilExpiry | Should -BeGreaterOrEqual 44
        $daysUntilExpiry | Should -BeLessOrEqual 46
    }

    It 'should warn when certificate expires soon (within 30 days)' {
        $cert = New-TestCertificate -NotAfter (Get-Date).AddDays(25)

        $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
        $shouldWarn = $daysUntilExpiry -le 30

        $shouldWarn | Should -Be $true
    }
}
