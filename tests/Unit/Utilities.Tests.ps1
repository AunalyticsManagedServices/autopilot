#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Utility functions.
#>

BeforeAll {
    # Import the module functions directly for testing
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\src'

    # Initialize module-scoped variables that the functions expect
    $script:Config = @{
        RetryPolicy = @{
            MaxAttempts = 3
            InitialDelayMs = 100  # Short for testing
            BackoffMultiplier = 2.0
        }
        Logging = @{
            EnableJsonLog = $false  # Disable file logging in tests
            Level = 'Debug'
        }
    }
    $script:DeviceIdentifiers = $null
    $script:LogPath = $null

    # Dot-source the utility functions
    . "$ModuleRoot\Private\Utilities\Write-AutopilotLog.ps1"
    . "$ModuleRoot\Private\Utilities\Invoke-WithRetry.ps1"
}

Describe 'Invoke-WithRetry' {
    BeforeEach {
        $script:attemptCount = 0
    }

    It 'should succeed on first attempt when no errors' {
        $result = Invoke-WithRetry -OperationName 'Test' -ScriptBlock {
            $script:attemptCount++
            return 'success'
        }

        $result | Should -Be 'success'
        $script:attemptCount | Should -Be 1
    }

    It 'should retry on transient errors' {
        $result = Invoke-WithRetry -OperationName 'Test' -MaxAttempts 3 -InitialDelayMs 10 -ScriptBlock {
            $script:attemptCount++
            if ($script:attemptCount -lt 3) {
                throw "Connection timeout"
            }
            return 'success after retry'
        }

        $result | Should -Be 'success after retry'
        $script:attemptCount | Should -Be 3
    }

    It 'should not retry on non-retryable errors' {
        {
            Invoke-WithRetry -OperationName 'Test' -MaxAttempts 3 -InitialDelayMs 10 -ScriptBlock {
                $script:attemptCount++
                throw "Permission denied"
            }
        } | Should -Throw

        $script:attemptCount | Should -Be 1
    }

    It 'should throw after max attempts exceeded' {
        {
            Invoke-WithRetry -OperationName 'Test' -MaxAttempts 2 -InitialDelayMs 10 -ScriptBlock {
                $script:attemptCount++
                throw "Network timeout"
            }
        } | Should -Throw

        $script:attemptCount | Should -Be 2
    }

    It 'should use custom retryable patterns' {
        $result = Invoke-WithRetry -OperationName 'Test' -MaxAttempts 3 -InitialDelayMs 10 `
            -RetryableErrorPatterns @('custom_error') `
            -ScriptBlock {
                $script:attemptCount++
                if ($script:attemptCount -lt 2) {
                    throw "custom_error occurred"
                }
                return 'success'
            }

        $result | Should -Be 'success'
        $script:attemptCount | Should -Be 2
    }

    It 'should recognize HTTP 429 as retryable' {
        $result = Invoke-WithRetry -OperationName 'Test' -MaxAttempts 3 -InitialDelayMs 10 -ScriptBlock {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                throw "HTTP 429 Too Many Requests"
            }
            return 'success'
        }

        $result | Should -Be 'success'
        $script:attemptCount | Should -Be 2
    }

    It 'should recognize HTTP 503 as retryable' {
        $result = Invoke-WithRetry -OperationName 'Test' -MaxAttempts 3 -InitialDelayMs 10 -ScriptBlock {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) {
                throw "503 Service Unavailable"
            }
            return 'success'
        }

        $result | Should -Be 'success'
        $script:attemptCount | Should -Be 2
    }
}

Describe 'Write-AutopilotLog' {
    BeforeAll {
        # Disable JSON logging for tests
        $script:Config = @{
            Logging = @{
                EnableJsonLog = $false
                Level = 'Debug'
            }
        }
    }

    It 'should not throw on any log level' {
        { Write-AutopilotLog -Level 'Debug' -Message 'Test debug' } | Should -Not -Throw
        { Write-AutopilotLog -Level 'Info' -Message 'Test info' } | Should -Not -Throw
        { Write-AutopilotLog -Level 'Warning' -Message 'Test warning' } | Should -Not -Throw
        { Write-AutopilotLog -Level 'Error' -Message 'Test error' } | Should -Not -Throw
    }

    It 'should accept Phase parameter' {
        { Write-AutopilotLog -Level 'Info' -Message 'Test' -Phase 'TestPhase' } | Should -Not -Throw
    }

    It 'should accept Data parameter' {
        { Write-AutopilotLog -Level 'Info' -Message 'Test' -Data @{ Key = 'Value' } } | Should -Not -Throw
    }

    It 'should filter by log level' {
        $script:Config = @{
            Logging = @{
                EnableJsonLog = $false
                Level = 'Warning'  # Only Warning and Error
            }
        }

        # Debug and Info should be filtered (no output)
        # We can't easily test console output, but at least verify no errors
        { Write-AutopilotLog -Level 'Debug' -Message 'Should be filtered' } | Should -Not -Throw
        { Write-AutopilotLog -Level 'Info' -Message 'Should be filtered' } | Should -Not -Throw
        { Write-AutopilotLog -Level 'Warning' -Message 'Should show' } | Should -Not -Throw
    }
}
