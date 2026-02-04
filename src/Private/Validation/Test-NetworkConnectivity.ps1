function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests network connectivity to required Microsoft endpoints.

    .DESCRIPTION
        Validates that the device can reach the Microsoft endpoints required
        for Autopilot deployment:
        - Microsoft Graph API
        - Microsoft Login (Entra ID)
        - PowerShell Gallery (for module installation)

    .PARAMETER Endpoints
        Optional custom list of endpoints to test.

    .OUTPUTS
        [bool] True if all endpoints are reachable.

    .EXAMPLE
        if (Test-NetworkConnectivity) { Write-Host "Network OK" }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [hashtable[]]$Endpoints
    )

    # Default endpoints if not specified
    if (-not $Endpoints) {
        $Endpoints = @(
            @{ Name = 'Microsoft Graph'; Host = 'graph.microsoft.com' },
            @{ Name = 'Microsoft Login'; Host = 'login.microsoftonline.com' },
            @{ Name = 'PowerShell Gallery'; Host = 'www.powershellgallery.com' }
        )
    }

    Write-AutopilotLog -Level Info -Message "Testing network connectivity" -Phase 'PreFlight'

    $allPassed = $true

    foreach ($endpoint in $Endpoints) {
        try {
            $result = Test-NetConnection -ComputerName $endpoint.Host -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop

            if ($result.TcpTestSucceeded) {
                Write-AutopilotLog -Level Info -Message "Network check passed: $($endpoint.Name)" -Phase 'PreFlight' -Data @{
                    Host         = $endpoint.Host
                    RemotePort   = 443
                    ResponseTime = $result.PingReplyDetails.RoundtripTime
                }
                Write-Host "  [OK] $($endpoint.Name) ($($endpoint.Host))" -ForegroundColor Green
            }
            else {
                Write-AutopilotLog -Level Error -Message "Network check failed: $($endpoint.Name)" -Phase 'PreFlight' -Data @{
                    Host = $endpoint.Host
                }
                Write-Host "  [FAIL] $($endpoint.Name) ($($endpoint.Host))" -ForegroundColor Red
                $allPassed = $false
            }
        }
        catch {
            Write-AutopilotLog -Level Error -Message "Network check error: $($endpoint.Name)" -Phase 'PreFlight' -Data @{
                Host  = $endpoint.Host
                Error = $_.Exception.Message
            }
            Write-Host "  [FAIL] $($endpoint.Name) ($($endpoint.Host)) - $($_.Exception.Message)" -ForegroundColor Red
            $allPassed = $false
        }
    }

    return $allPassed
}
