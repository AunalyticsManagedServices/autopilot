function Test-ConfigValidation {
    <#
    .SYNOPSIS
        Validates the Autopilot configuration.

    .DESCRIPTION
        Checks that all required configuration values are present and valid.
        Returns a validation result object with any errors found.

    .PARAMETER Config
        The configuration hashtable to validate.

    .OUTPUTS
        [PSCustomObject] with IsValid (bool) and Errors (string[]) properties.

    .EXAMPLE
        $result = Test-ConfigValidation -Config $config
        if (-not $result.IsValid) {
            Write-Error "Config errors: $($result.Errors -join ', ')"
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Required fields
    if ([string]::IsNullOrWhiteSpace($Config.TenantId)) {
        $errors.Add("TenantId is required")
    }
    elseif ($Config.TenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        $errors.Add("TenantId must be a valid GUID")
    }

    if ([string]::IsNullOrWhiteSpace($Config.ClientId)) {
        $errors.Add("ClientId is required")
    }
    elseif ($Config.ClientId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        $errors.Add("ClientId must be a valid GUID")
    }

    # Key Vault validation
    if ($Config.KeyVault) {
        if ([string]::IsNullOrWhiteSpace($Config.KeyVault.Name)) {
            $errors.Add("KeyVault.Name is required")
        }
        elseif ($Config.KeyVault.Name -notmatch '^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$') {
            $errors.Add("KeyVault.Name must be 3-24 characters, alphanumeric and hyphens, starting with a letter")
        }

        if ([string]::IsNullOrWhiteSpace($Config.KeyVault.CertSecretName)) {
            $errors.Add("KeyVault.CertSecretName is required")
        }

        if ($Config.KeyVault.SubscriptionId -and
            $Config.KeyVault.SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            $errors.Add("KeyVault.SubscriptionId must be a valid GUID if specified")
        }
    }
    else {
        $errors.Add("KeyVault configuration section is required")
    }

    # PostAction validation
    $validPostActions = @('Restart', 'Shutdown', 'Sysprep', 'None')
    if ($Config.PostAction -and $Config.PostAction -notin $validPostActions) {
        $errors.Add("PostAction must be one of: $($validPostActions -join ', ')")
    }

    # Run validation
    $validRunOptions = @('WindowsSettings', 'NetworkingWireless', 'UpdateDrivers', 'WindowsUpdate', 'Restart', 'Shutdown', 'Sysprep', 'MDMDiag', 'None')
    if ($Config.Run -and $Config.Run -notin $validRunOptions) {
        $errors.Add("Run must be one of: $($validRunOptions -join ', ')")
    }

    # Retry policy validation
    if ($Config.RetryPolicy) {
        if ($Config.RetryPolicy.MaxAttempts -lt 1 -or $Config.RetryPolicy.MaxAttempts -gt 10) {
            $errors.Add("RetryPolicy.MaxAttempts must be between 1 and 10")
        }
        if ($Config.RetryPolicy.InitialDelayMs -lt 100 -or $Config.RetryPolicy.InitialDelayMs -gt 60000) {
            $errors.Add("RetryPolicy.InitialDelayMs must be between 100 and 60000")
        }
        if ($Config.RetryPolicy.BackoffMultiplier -lt 1.0 -or $Config.RetryPolicy.BackoffMultiplier -gt 5.0) {
            $errors.Add("RetryPolicy.BackoffMultiplier must be between 1.0 and 5.0")
        }
    }

    # Logging level validation
    $validLogLevels = @('Debug', 'Info', 'Warning', 'Error')
    if ($Config.Logging -and $Config.Logging.Level -and $Config.Logging.Level -notin $validLogLevels) {
        $errors.Add("Logging.Level must be one of: $($validLogLevels -join ', ')")
    }

    # Propagation delays validation
    if ($Config.PropagationDelays) {
        foreach ($key in @('EntraCleanup', 'IntuneCleanup', 'AutopilotCleanup')) {
            if ($Config.PropagationDelays.ContainsKey($key)) {
                $value = $Config.PropagationDelays[$key]
                if ($value -lt 0 -or $value -gt 300) {
                    $errors.Add("PropagationDelays.$key must be between 0 and 300 seconds")
                }
            }
        }
    }

    # TimeZone validation - basic check
    if ($Config.TimeZone) {
        try {
            $null = [System.TimeZoneInfo]::FindSystemTimeZoneById($Config.TimeZone)
        }
        catch {
            $errors.Add("TimeZone '$($Config.TimeZone)' is not a valid Windows time zone ID")
        }
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors.ToArray()
    }
}
