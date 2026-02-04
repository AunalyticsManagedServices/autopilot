function Test-GraphConnection {
    <#
    .SYNOPSIS
        Tests if there is an active Microsoft Graph connection.

    .DESCRIPTION
        Checks whether a Microsoft Graph connection is currently established.
        Optionally validates that the connection has the required scopes.

    .PARAMETER RequiredScopes
        Optional array of scopes to verify the connection has.

    .OUTPUTS
        [bool] True if connected (and has required scopes if specified).

    .EXAMPLE
        if (Test-GraphConnection) { Write-Host "Connected" }
        if (Test-GraphConnection -RequiredScopes 'DeviceManagementManagedDevices.ReadWrite.All') { ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string[]]$RequiredScopes
    )

    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue

        if (-not $context) {
            Write-AutopilotLog -Level Debug -Message "No Microsoft Graph context found" -Phase 'GraphAuth'
            return $false
        }

        # If no specific scopes required, just return connected status
        if (-not $RequiredScopes) {
            return $true
        }

        # Check for required scopes
        $currentScopes = $context.Scopes
        $missingScopes = @()

        foreach ($scope in $RequiredScopes) {
            # Check for exact match or .default scope
            if ($currentScopes -notcontains $scope -and $currentScopes -notcontains '.default') {
                $missingScopes += $scope
            }
        }

        if ($missingScopes.Count -gt 0) {
            Write-AutopilotLog -Level Warning -Message "Graph connection missing required scopes" -Phase 'GraphAuth' -Data @{
                MissingScopes = $missingScopes -join ', '
                CurrentScopes = $currentScopes -join ', '
            }
            return $false
        }

        return $true
    }
    catch {
        Write-AutopilotLog -Level Debug -Message "Error checking Graph connection: $($_.Exception.Message)" -Phase 'GraphAuth'
        return $false
    }
}
