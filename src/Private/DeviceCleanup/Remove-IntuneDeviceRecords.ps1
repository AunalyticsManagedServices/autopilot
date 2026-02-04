function Remove-IntuneDeviceRecords {
    <#
    .SYNOPSIS
        Removes existing Intune managed device records for this device.

    .DESCRIPTION
        Searches for and removes Intune managed device records matching
        the current device's serial number to prevent enrollment conflicts.

    .PARAMETER State
        Optional deployment state object for tracking cleaned devices.

    .OUTPUTS
        [int] The number of devices removed.

    .EXAMPLE
        $removed = Remove-IntuneDeviceRecords
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
        Write-AutopilotLog -Level Warning -Message "Could not retrieve serial number for Intune device lookup" -Phase 'IntuneCleanup'
        return 0
    }

    Write-AutopilotLog -Level Info -Message "Checking for existing Intune managed device records" -Phase 'IntuneCleanup' -Data @{
        SerialNumber = $serialNumber
    }

    $devicesRemoved = 0

    try {
        # Get managed devices by serial number
        $managedDevices = Invoke-WithRetry -OperationName 'Get Intune managed devices' -ScriptBlock {
            Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$serialNumber'" -ErrorAction SilentlyContinue
        }

        if ($managedDevices -and @($managedDevices).Count -gt 0) {
            $deviceCount = @($managedDevices).Count
            Write-AutopilotLog -Level Warning -Message "Found $deviceCount existing Intune managed device(s)" -Phase 'IntuneCleanup'

            foreach ($device in $managedDevices) {
                # Skip if already cleaned in this session
                if ($State -and $State.WasDeviceCleaned($device.Id)) {
                    Write-AutopilotLog -Level Debug -Message "Skipping device (already cleaned): $($device.Id)" -Phase 'IntuneCleanup'
                    continue
                }

                Write-AutopilotLog -Level Info -Message "Removing Intune managed device" -Phase 'IntuneCleanup' -Data @{
                    DeviceName   = $device.DeviceName
                    SerialNumber = $device.SerialNumber
                    DeviceId     = $device.Id
                }

                try {
                    Invoke-WithRetry -OperationName "Remove Intune device $($device.DeviceName)" -ScriptBlock {
                        Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id -ErrorAction Stop
                    }

                    Write-AutopilotLog -Level Info -Message "Successfully removed Intune device: $($device.DeviceName)" -Phase 'IntuneCleanup'
                    $devicesRemoved++

                    # Record cleaned device in state
                    if ($State) {
                        $State.RecordCleanedDevice($device.Id)
                    }
                }
                catch {
                    Write-AutopilotLog -Level Warning -Message "Failed to remove Intune device: $($device.DeviceName)" -Phase 'IntuneCleanup' -Data @{
                        Error = $_.Exception.Message
                    }
                }
            }

            # Wait for propagation if we removed anything
            if ($devicesRemoved -gt 0) {
                $config = Get-AutopilotConfig
                $delay = $config.PropagationDelays.IntuneCleanup

                Write-AutopilotLog -Level Info -Message "Waiting $delay seconds for Intune deletion to propagate" -Phase 'IntuneCleanup'
                Start-Sleep -Seconds $delay
            }
        }
        else {
            Write-AutopilotLog -Level Info -Message "No existing Intune managed device records found" -Phase 'IntuneCleanup'
        }
    }
    catch {
        Write-AutopilotLog -Level Warning -Message "Error during Intune device cleanup" -Phase 'IntuneCleanup' -Data @{
            Error = $_.Exception.Message
        }
    }

    return $devicesRemoved
}
