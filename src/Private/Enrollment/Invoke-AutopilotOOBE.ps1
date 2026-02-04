function Invoke-AutopilotOOBE {
    <#
    .SYNOPSIS
        High-level function to invoke the complete Autopilot OOBE process.

    .DESCRIPTION
        Orchestrates the full Autopilot OOBE registration process:
        1. Sets time zone
        2. Validates groups (optional)
        3. Launches AutopilotOOBE GUI

        This function is called after authentication and device cleanup.

    .PARAMETER Config
        The Autopilot configuration hashtable.

    .PARAMETER SkipGroupValidation
        Skip Entra group validation.

    .OUTPUTS
        [DeploymentResult]

    .EXAMPLE
        $result = Invoke-AutopilotOOBE -Config $config
    #>
    [CmdletBinding()]
    [OutputType([DeploymentResult])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter()]
        [switch]$SkipGroupValidation
    )

    Write-AutopilotLog -Level Info -Message "Starting AutopilotOOBE registration process" -Phase 'Enrollment'

    # Set time zone
    if ($Config.TimeZone) {
        Write-AutopilotLog -Level Info -Message "Setting time zone: $($Config.TimeZone)" -Phase 'Enrollment'
        try {
            Set-TimeZone -Id $Config.TimeZone -ErrorAction Stop
            Write-AutopilotLog -Level Info -Message "Time zone set successfully" -Phase 'Enrollment'
        }
        catch {
            Write-AutopilotLog -Level Warning -Message "Failed to set time zone" -Phase 'Enrollment' -Data @{
                TimeZone = $Config.TimeZone
                Error    = $_.Exception.Message
            }
            # Non-fatal - continue
        }
    }

    # Validate groups (unless skipped)
    if (-not $SkipGroupValidation -and -not $Config.SkipGroupValidation) {
        $groupsToValidate = $Config.GroupOptions
        if ($groupsToValidate -and $groupsToValidate.Count -gt 0) {
            Write-AutopilotLog -Level Info -Message "Validating Entra groups" -Phase 'Enrollment'

            $validationResult = Test-EntraGroupExists -GroupNames $groupsToValidate
            if (-not $validationResult) {
                Write-AutopilotLog -Level Warning -Message "Some groups could not be validated - continuing anyway" -Phase 'Enrollment'
            }
            else {
                Write-AutopilotLog -Level Info -Message "All groups validated successfully" -Phase 'Enrollment'
            }
        }
    }
    else {
        Write-AutopilotLog -Level Info -Message "Skipping group validation (disabled in config)" -Phase 'Enrollment'
    }

    # Launch AutopilotOOBE
    try {
        Register-AutopilotDevice -Config $Config
        return [DeploymentResult]::Ok("AutopilotOOBE completed successfully", 'Enrollment')
    }
    catch {
        return [DeploymentResult]::Fail("AutopilotOOBE failed: $($_.Exception.Message)", 'Enrollment', $_)
    }
}
