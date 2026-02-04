#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Device Cleanup functions.
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
            Level = 'Warning'  # Reduce noise in tests
        }
        PropagationDelays = @{
            EntraCleanup = 0
            IntuneCleanup = 0
            AutopilotCleanup = 0
        }
    }
    $script:DeviceIdentifiers = $null
    $script:LogPath = $null

    # Dot-source required functions
    . "$ModuleRoot\Private\Utilities\Write-AutopilotLog.ps1"
    . "$ModuleRoot\Private\Utilities\Invoke-WithRetry.ps1"
    . "$ModuleRoot\Private\DeviceCleanup\Get-DeviceIdentifiers.ps1"
    . "$ModuleRoot\Private\Configuration\Get-AutopilotConfig.ps1"
    . "$ModuleRoot\Private\Configuration\Merge-ConfigWithDefaults.ps1"
    . "$ModuleRoot\Private\Configuration\Test-ConfigValidation.ps1"

    # Mock Get-AutopilotConfig to return test config
    Mock Get-AutopilotConfig {
        return $script:Config
    }
}

Describe 'Get-DeviceIdentifiers' {
    BeforeEach {
        # Reset cache
        $script:DeviceIdentifiers = $null
    }

    It 'should return device information' {
        # Mock CIM calls
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = 'TEST123' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{
                    Manufacturer = 'TestMfg'
                    Model = 'TestModel'
                }
            }
        }

        $result = Get-DeviceIdentifiers

        $result.SerialNumber | Should -Be 'TEST123'
        $result.Manufacturer | Should -Be 'TestMfg'
        $result.Model | Should -Be 'TestModel'
        $result.ComputerName | Should -Be $env:COMPUTERNAME
    }

    It 'should cache results' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = 'CACHED123' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{
                    Manufacturer = 'CachedMfg'
                    Model = 'CachedModel'
                }
            }
        }

        # First call
        $result1 = Get-DeviceIdentifiers

        # Change mock
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = 'DIFFERENT' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{
                    Manufacturer = 'DifferentMfg'
                    Model = 'DifferentModel'
                }
            }
        }

        # Second call should return cached
        $result2 = Get-DeviceIdentifiers

        $result2.SerialNumber | Should -Be 'CACHED123'
    }

    It 'should refresh cache with -Force' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = 'FIRST' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{ Manufacturer = 'First'; Model = 'First' }
            }
        }

        $result1 = Get-DeviceIdentifiers

        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = 'SECOND' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{ Manufacturer = 'Second'; Model = 'Second' }
            }
        }

        $result2 = Get-DeviceIdentifiers -Force

        $result2.SerialNumber | Should -Be 'SECOND'
    }

    It 'should handle empty serial number' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_BIOS') {
                return @{ SerialNumber = '' }
            }
            if ($ClassName -eq 'Win32_ComputerSystem') {
                return @{ Manufacturer = 'Test'; Model = 'Test' }
            }
        }

        $result = Get-DeviceIdentifiers

        $result.SerialNumber | Should -Be 'UNKNOWN'
    }
}
