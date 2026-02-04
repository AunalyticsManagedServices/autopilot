function Get-DeviceSerialNumber {
    <#
    .SYNOPSIS
        Gets the device serial number with caching.

    .DESCRIPTION
        Retrieves the device serial number from WMI/CIM.
        Uses module-scoped caching to avoid repeated WMI queries.

    .OUTPUTS
        [string] The device serial number.

    .EXAMPLE
        $serial = Get-DeviceSerialNumber
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Return cached value if available
    if ($script:DeviceIdentifiers) {
        return $script:DeviceIdentifiers.SerialNumber
    }

    # Get device identifiers (which caches all device info)
    $identifiers = Get-DeviceIdentifiers
    return $identifiers.SerialNumber
}
