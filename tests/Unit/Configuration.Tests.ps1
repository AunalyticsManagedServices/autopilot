#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Configuration functions.
#>

BeforeAll {
    # Import the module functions directly for testing
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\src'

    # Dot-source the configuration functions
    . "$ModuleRoot\Private\Configuration\Merge-ConfigWithDefaults.ps1"
    . "$ModuleRoot\Private\Configuration\Test-ConfigValidation.ps1"
}

Describe 'Merge-ConfigWithDefaults' {
    It 'should return defaults when given empty config' {
        $result = Merge-ConfigWithDefaults -Config @{}

        $result.RetryPolicy.MaxAttempts | Should -Be 3
        $result.RetryPolicy.InitialDelayMs | Should -Be 1000
        $result.CleanupExistingDevices | Should -Be $true
        $result.PostAction | Should -Be 'Restart'
    }

    It 'should override defaults with user config' {
        $config = @{
            TimeZone = 'Pacific Standard Time'
            PostAction = 'Shutdown'
        }

        $result = Merge-ConfigWithDefaults -Config $config

        $result.TimeZone | Should -Be 'Pacific Standard Time'
        $result.PostAction | Should -Be 'Shutdown'
    }

    It 'should merge nested hashtables' {
        $config = @{
            RetryPolicy = @{
                MaxAttempts = 5
            }
        }

        $result = Merge-ConfigWithDefaults -Config $config

        $result.RetryPolicy.MaxAttempts | Should -Be 5
        $result.RetryPolicy.InitialDelayMs | Should -Be 1000  # Default preserved
    }

    It 'should compute password secret name from cert secret name' {
        $config = @{
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'MyCert'
            }
        }

        $result = Merge-ConfigWithDefaults -Config $config

        $result.KeyVault.PasswordSecretName | Should -Be 'MyCert-Password'
    }

    It 'should not override explicit password secret name' {
        $config = @{
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'MyCert'
                PasswordSecretName = 'CustomPassword'
            }
        }

        $result = Merge-ConfigWithDefaults -Config $config

        $result.KeyVault.PasswordSecretName | Should -Be 'CustomPassword'
    }

    It 'should include DefaultGroup in GroupOptions if not present' {
        $config = @{
            DefaultGroup = 'MyGroup'
            GroupOptions = @('OtherGroup')
        }

        $result = Merge-ConfigWithDefaults -Config $config

        $result.GroupOptions | Should -Contain 'MyGroup'
        $result.GroupOptions | Should -Contain 'OtherGroup'
    }
}

Describe 'Test-ConfigValidation' {
    It 'should fail if TenantId is missing' {
        $config = @{
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'cert'
            }
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain 'TenantId is required'
    }

    It 'should fail if TenantId is not a valid GUID' {
        $config = @{
            TenantId = 'not-a-guid'
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'cert'
            }
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain 'TenantId must be a valid GUID'
    }

    It 'should fail if KeyVault.Name is missing' {
        $config = @{
            TenantId = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                CertSecretName = 'cert'
            }
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain 'KeyVault.Name is required'
    }

    It 'should fail if PostAction is invalid' {
        $config = @{
            TenantId = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'cert'
            }
            PostAction = 'InvalidAction'
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $false
        $result.Errors | Should -Match 'PostAction must be one of'
    }

    It 'should pass with valid configuration' {
        $config = @{
            TenantId = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'cert'
            }
            PostAction = 'Restart'
            TimeZone = 'Eastern Standard Time'
            RetryPolicy = @{
                MaxAttempts = 3
                InitialDelayMs = 1000
                BackoffMultiplier = 2.0
            }
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $true
        $result.Errors.Count | Should -Be 0
    }

    It 'should validate RetryPolicy bounds' {
        $config = @{
            TenantId = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
            ClientId = 'bf98483c-c034-4338-802a-8bb0d84fb462'
            KeyVault = @{
                Name = 'test-vault'
                CertSecretName = 'cert'
            }
            RetryPolicy = @{
                MaxAttempts = 100  # Too high
                InitialDelayMs = 50  # Too low
                BackoffMultiplier = 10.0  # Too high
            }
        }

        $result = Test-ConfigValidation -Config $config

        $result.IsValid | Should -Be $false
        $result.Errors | Should -Contain 'RetryPolicy.MaxAttempts must be between 1 and 10'
        $result.Errors | Should -Contain 'RetryPolicy.InitialDelayMs must be between 100 and 60000'
        $result.Errors | Should -Contain 'RetryPolicy.BackoffMultiplier must be between 1.0 and 5.0'
    }
}
