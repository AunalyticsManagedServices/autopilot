function Register-AutopilotDevice {
    <#
    .SYNOPSIS
        Registers the current device with Windows Autopilot.

    .DESCRIPTION
        Invokes the AutopilotOOBE module to register the device with
        Windows Autopilot using the configured settings.

        This function prepares the parameters and launches the AutopilotOOBE
        GUI for user interaction (group selection, computer naming, etc.).

    .PARAMETER Config
        The Autopilot configuration hashtable. If not provided, loads from Get-AutopilotConfig.

    .OUTPUTS
        [void]

    .EXAMPLE
        Register-AutopilotDevice
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Config
    )

    if (-not $Config) {
        $Config = Get-AutopilotConfig
    }

    Write-AutopilotLog -Level Info -Message "Preparing AutopilotOOBE parameters" -Phase 'Enrollment'

    # Build AutopilotOOBE parameters from config
    $params = [ordered]@{
        Title                       = $Config.Title
        AssignedUserExample         = $Config.AssignedUserExample
        AssignedComputerNameExample = $Config.AssignedComputerNameExample
        AddToGroup                  = $Config.DefaultGroup
        AddToGroupOptions           = $Config.GroupOptions
        GroupTag                    = $Config.DefaultGroupTag
        GroupTagOptions             = $Config.GroupTagOptions
        PostAction                  = $Config.PostAction
        Assign                      = $Config.Assign
        Run                         = $Config.Run
        Docs                        = $Config.DocsUrl
    }

    # Log the parameters
    Write-AutopilotLog -Level Info -Message "AutopilotOOBE parameters configured" -Phase 'Enrollment' -Data $params

    # Display parameters to console for visibility
    Write-Host ""
    Write-Host "Starting AutopilotOOBE with configured parameters:" -ForegroundColor White
    foreach ($key in $params.Keys) {
        $value = $params[$key]
        if ($value -is [array]) {
            $value = $value -join ', '
        }
        Write-Host "  $($key): $value" -ForegroundColor Yellow
    }
    Write-Host ""

    # Launch AutopilotOOBE
    Write-AutopilotLog -Level Info -Message "Launching AutopilotOOBE GUI" -Phase 'Enrollment'

    try {
        AutopilotOOBE @params
        Write-AutopilotLog -Level Info -Message "AutopilotOOBE completed" -Phase 'Enrollment'
    }
    catch {
        Write-AutopilotLog -Level Error -Message "AutopilotOOBE failed" -Phase 'Enrollment' -Data @{
            Error = $_.Exception.Message
        }
        throw
    }
}
