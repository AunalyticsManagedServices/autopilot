function Remove-AutopilotRegistration {
    <#
    .SYNOPSIS
        Removes existing Autopilot device registrations for this device.

    .DESCRIPTION
        Searches for and removes Windows Autopilot device identity records
        matching the current device's serial number to allow re-registration.

    .PARAMETER State
        Optional deployment state object for tracking cleaned devices.

    .OUTPUTS
        [int] The number of registrations removed.

    .EXAMPLE
        $removed = Remove-AutopilotRegistration
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [DeploymentState]$State
    )

    $deviceInfo = Get-DeviceIdentifiers
    $serialNumber = $deviceInfo.SerialNumber

    if ([string]::IsNullOrWhiteSpace($serialNumber) -or $serialNumber -eq 'UNKNOWN') {
        Write-AutopilotLog -Level Warning -Message "Could not retrieve serial number for Autopilot lookup" -Phase 'AutopilotCleanup'
        return 0
    }

    Write-AutopilotLog -Level Info -Message "Checking for existing Autopilot registration" -Phase 'AutopilotCleanup' -Data @{
        SerialNumber = $serialNumber
    }

    $devicesRemoved = 0

    try {
        # Get Autopilot device identities by serial number
        $existingDevices = Invoke-WithRetry -OperationName 'Get Autopilot devices' -ScriptBlock {
            Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
        }

        if ($existingDevices -and @($existingDevices).Count -gt 0) {
            $deviceCount = @($existingDevices).Count
            Write-AutopilotLog -Level Warning -Message "Found $deviceCount existing Autopilot registration(s)" -Phase 'AutopilotCleanup'

            foreach ($device in $existingDevices) {
                # Skip if already cleaned in this session
                if ($State -and $State.WasDeviceCleaned($device.Id)) {
                    Write-AutopilotLog -Level Debug -Message "Skipping device (already cleaned): $($device.Id)" -Phase 'AutopilotCleanup'
                    continue
                }

                Write-AutopilotLog -Level Info -Message "Removing Autopilot registration" -Phase 'AutopilotCleanup' -Data @{
                    SerialNumber = $device.SerialNumber
                    DeviceId     = $device.Id
                    GroupTag     = $device.GroupTag
                }

                try {
                    Invoke-WithRetry -OperationName "Remove Autopilot device $($device.SerialNumber)" -ScriptBlock {
                        Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $device.Id -ErrorAction Stop
                    }

                    Write-AutopilotLog -Level Info -Message "Successfully removed Autopilot registration: $($device.SerialNumber)" -Phase 'AutopilotCleanup'
                    $devicesRemoved++

                    # Record cleaned device in state
                    if ($State) {
                        $State.RecordCleanedDevice($device.Id)
                    }
                }
                catch {
                    Write-AutopilotLog -Level Warning -Message "Failed to remove Autopilot registration" -Phase 'AutopilotCleanup' -Data @{
                        SerialNumber = $device.SerialNumber
                        Error        = $_.Exception.Message
                    }
                }
            }

            # Wait for propagation if we removed anything
            if ($devicesRemoved -gt 0) {
                $config = Get-AutopilotConfig
                $delay = $config.PropagationDelays.AutopilotCleanup

                Write-AutopilotLog -Level Info -Message "Waiting $delay seconds for Autopilot deletion to propagate" -Phase 'AutopilotCleanup'
                Start-Sleep -Seconds $delay
            }
        }
        else {
            Write-AutopilotLog -Level Info -Message "No existing Autopilot registration found" -Phase 'AutopilotCleanup'
        }
    }
    catch {
        Write-AutopilotLog -Level Warning -Message "Error during Autopilot cleanup" -Phase 'AutopilotCleanup' -Data @{
            Error = $_.Exception.Message
        }
    }

    return $devicesRemoved
}
