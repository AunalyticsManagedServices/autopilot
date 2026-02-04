function Merge-ConfigWithDefaults {
    <#
    .SYNOPSIS
        Merges user configuration with default values.

    .DESCRIPTION
        Takes a loaded configuration hashtable and fills in any missing values
        with sensible defaults. This ensures all expected keys exist.

    .PARAMETER Config
        The configuration hashtable loaded from the config file.

    .OUTPUTS
        [hashtable] The merged configuration with defaults applied.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Define default configuration
    $defaults = @{
        # Key Vault defaults
        KeyVault = @{
            Name               = ''
            CertSecretName     = 'AutopilotOOBE-Cert'
            PasswordSecretName = ''
            SubscriptionId     = ''
        }

        # Required - no defaults
        TenantId = ''
        ClientId = ''

        # Deployment settings
        Title                       = 'Autopilot Registration'
        AssignedUserExample         = 'username@contoso.com'
        AssignedComputerNameExample = 'PC####'
        DefaultGroup                = ''
        GroupOptions                = @()
        DefaultGroupTag             = 'Standard'
        GroupTagOptions             = @('Standard')

        # Regional settings
        TimeZone = 'Eastern Standard Time'

        # Behavior settings
        CleanupExistingDevices = $true
        SkipGroupValidation    = $false
        PostAction             = 'Restart'
        Run                    = 'WindowsSettings'
        Assign                 = $true
        DocsUrl                = 'https://autopilotoobe.osdeploy.com/'

        # Retry policy
        RetryPolicy = @{
            MaxAttempts       = 3
            InitialDelayMs    = 1000
            BackoffMultiplier = 2.0
        }

        # Logging
        Logging = @{
            EnableJsonLog = $true
            Level         = 'Info'
            Path          = ''
        }

        # Propagation delays
        PropagationDelays = @{
            EntraCleanup     = 15
            IntuneCleanup    = 10
            AutopilotCleanup = 10
        }
    }

    # Deep merge function
    $mergeHashtables = {
        param([hashtable]$Default, [hashtable]$Override)

        $result = @{}

        # Start with all default keys
        foreach ($key in $Default.Keys) {
            if ($Override.ContainsKey($key)) {
                if ($Default[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
                    # Recursively merge nested hashtables
                    $result[$key] = & $mergeHashtables $Default[$key] $Override[$key]
                }
                else {
                    # Override wins
                    $result[$key] = $Override[$key]
                }
            }
            else {
                # Use default
                $result[$key] = $Default[$key]
            }
        }

        # Add any extra keys from override that aren't in defaults
        foreach ($key in $Override.Keys) {
            if (-not $Default.ContainsKey($key)) {
                $result[$key] = $Override[$key]
            }
        }

        return $result
    }

    $merged = & $mergeHashtables $defaults $Config

    # Apply computed defaults
    if (-not $merged.KeyVault.PasswordSecretName -and $merged.KeyVault.CertSecretName) {
        $merged.KeyVault.PasswordSecretName = "$($merged.KeyVault.CertSecretName)-Password"
    }

    # Ensure GroupOptions includes DefaultGroup
    if ($merged.DefaultGroup -and $merged.GroupOptions -notcontains $merged.DefaultGroup) {
        $merged.GroupOptions = @($merged.DefaultGroup) + $merged.GroupOptions
    }

    # Ensure GroupTagOptions includes DefaultGroupTag
    if ($merged.DefaultGroupTag -and $merged.GroupTagOptions -notcontains $merged.DefaultGroupTag) {
        $merged.GroupTagOptions = @($merged.DefaultGroupTag) + $merged.GroupTagOptions
    }

    return $merged
}
