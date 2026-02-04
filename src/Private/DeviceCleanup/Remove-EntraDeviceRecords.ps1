function Remove-EntraDeviceRecords {
    <#
    .SYNOPSIS
        Removes existing Entra ID device registrations for this device.

    .DESCRIPTION
        Cleans up both "Microsoft Entra joined" and "Microsoft Entra registered"
        device records to prevent "device already enrolled" errors (0x8018000a).

        Searches for devices matching:
        - Current computer name (exact match)
        - Devices starting with patterns like WAU#### (if applicable)

    .PARAMETER State
        Optional deployment state object for tracking cleaned devices.

    .OUTPUTS
        [int] The number of devices removed.

    .EXAMPLE
        $removed = Remove-EntraDeviceRecords
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [DeploymentState]$State
    )

    $deviceInfo = Get-DeviceIdentifiers
    $computerName = $deviceInfo.ComputerName

    Write-AutopilotLog -Level Info -Message "Checking for existing Entra ID device registrations" -Phase 'EntraCleanup' -Data @{
        ComputerName = $computerName
        SerialNumber = $deviceInfo.SerialNumber
    }

    $devicesRemoved = 0
    $existingDevices = @()

    try {
        # Search by exact computer name
        if (-not [string]::IsNullOrWhiteSpace($computerName)) {
            $byName = Invoke-WithRetry -OperationName 'Get Entra devices by name' -ScriptBlock {
                Get-MgDevice -Filter "displayName eq '$computerName'" -ErrorAction SilentlyContinue
            }
            if ($byName) { $existingDevices += $byName }
        }

        # Search for devices with patterns like WAU#### (Aunalytics naming convention)
        if ($computerName -match '^WAU\d+') {
            $pattern = $computerName
            $byPattern = Invoke-WithRetry -OperationName 'Get Entra devices by pattern' -ScriptBlock {
                Get-MgDevice -Filter "startsWith(displayName,'$pattern')" -ErrorAction SilentlyContinue
            }
            if ($byPattern) { $existingDevices += $byPattern }
        }

        # Deduplicate by device ID
        $existingDevices = $existingDevices | Sort-Object -Property Id -Unique

        if ($existingDevices -and $existingDevices.Count -gt 0) {
            $deviceCount = @($existingDevices).Count
            Write-AutopilotLog -Level Warning -Message "Found $deviceCount existing Entra device record(s)" -Phase 'EntraCleanup'

            foreach ($device in $existingDevices) {
                # Skip if already cleaned in this session (for resume scenarios)
                if ($State -and $State.WasDeviceCleaned($device.Id)) {
                    Write-AutopilotLog -Level Debug -Message "Skipping device (already cleaned): $($device.Id)" -Phase 'EntraCleanup'
                    continue
                }

                $trustType = switch ($device.TrustType) {
                    'AzureAd' { 'Microsoft Entra joined' }
                    'Workplace' { 'Microsoft Entra registered' }
                    'ServerAd' { 'Hybrid Azure AD joined' }
                    default { $device.TrustType }
                }

                Write-AutopilotLog -Level Info -Message "Removing Entra device" -Phase 'EntraCleanup' -Data @{
                    DisplayName = $device.DisplayName
                    TrustType   = $trustType
                    DeviceId    = $device.Id
                }

                try {
                    Invoke-WithRetry -OperationName "Remove Entra device $($device.DisplayName)" -ScriptBlock {
                        Remove-MgDevice -DeviceId $device.Id -ErrorAction Stop
                    }

                    Write-AutopilotLog -Level Info -Message "Successfully removed Entra device: $($device.DisplayName)" -Phase 'EntraCleanup'
                    $devicesRemoved++

                    # Record cleaned device in state
                    if ($State) {
                        $State.RecordCleanedDevice($device.Id)
                    }
                }
                catch {
                    Write-AutopilotLog -Level Warning -Message "Failed to remove Entra device: $($device.DisplayName)" -Phase 'EntraCleanup' -Data @{
                        Error = $_.Exception.Message
                    }
                }
            }

            # Wait for propagation if we removed anything
            if ($devicesRemoved -gt 0) {
                $config = Get-AutopilotConfig
                $delay = $config.PropagationDelays.EntraCleanup

                Write-AutopilotLog -Level Info -Message "Waiting $delay seconds for Entra deletion to propagate" -Phase 'EntraCleanup'
                Start-Sleep -Seconds $delay
            }
        }
        else {
            Write-AutopilotLog -Level Info -Message "No existing Entra device records found" -Phase 'EntraCleanup'
        }
    }
    catch {
        Write-AutopilotLog -Level Warning -Message "Error during Entra device cleanup" -Phase 'EntraCleanup' -Data @{
            Error = $_.Exception.Message
        }
    }

    return $devicesRemoved
}
