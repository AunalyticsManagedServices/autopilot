function Get-DeviceIdentifiers {
    <#
    .SYNOPSIS
        Retrieves and caches device identifiers.

    .DESCRIPTION
        Gets device information from WMI/CIM including serial number, computer name,
        manufacturer, and model. Results are cached at the module scope to avoid
        repeated WMI queries throughout the deployment process.

    .PARAMETER Force
        Force a refresh of the cached device identifiers.

    .OUTPUTS
        [PSCustomObject] with SerialNumber, ComputerName, Manufacturer, Model, and RetrievedAt properties.

    .EXAMPLE
        $device = Get-DeviceIdentifiers
        Write-Host "Serial: $($device.SerialNumber)"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Force
    )

    # Return cached value if available and not forcing refresh
    if ($script:DeviceIdentifiers -and -not $Force) {
        return $script:DeviceIdentifiers
    }

    Write-AutopilotLog -Level Debug -Message "Retrieving device identifiers from WMI" -Phase 'DeviceInfo'

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    catch {
        throw "Failed to retrieve device information from WMI: $($_.Exception.Message)"
    }

    $serialNumber = $bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($serialNumber)) {
        Write-AutopilotLog -Level Warning -Message "Device serial number is empty or null" -Phase 'DeviceInfo'
        $serialNumber = 'UNKNOWN'
    }

    $identifiers = [PSCustomObject]@{
        SerialNumber = $serialNumber.Trim()
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $system.Manufacturer
        Model        = $system.Model
        RetrievedAt  = Get-Date
    }

    Write-AutopilotLog -Level Info -Message "Device identifiers retrieved" -Phase 'DeviceInfo' -Data @{
        SerialNumber = $identifiers.SerialNumber
        ComputerName = $identifiers.ComputerName
        Manufacturer = $identifiers.Manufacturer
        Model        = $identifiers.Model
    }

    # Cache the identifiers
    $script:DeviceIdentifiers = $identifiers

    return $identifiers
}
