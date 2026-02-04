function Connect-GraphWithCertificate {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph using certificate-based authentication.

    .DESCRIPTION
        Establishes a connection to Microsoft Graph API using an app registration
        with certificate-based authentication. This enables fully automated,
        zero-prompt deployment scenarios.

    .PARAMETER TenantId
        The Entra ID tenant ID (GUID).

    .PARAMETER ClientId
        The app registration client ID (GUID).

    .PARAMETER Certificate
        The X509Certificate2 object for authentication.

    .OUTPUTS
        [bool] True if connected successfully.

    .EXAMPLE
        $connected = Connect-GraphWithCertificate -TenantId $tenantId -ClientId $clientId -Certificate $cert
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    Write-AutopilotLog -Level Info -Message "Connecting to Microsoft Graph" -Phase 'GraphAuth' -Data @{
        TenantId   = $TenantId
        ClientId   = $ClientId
        Thumbprint = $Certificate.Thumbprint
    }

    try {
        Invoke-WithRetry -OperationName 'Connect to Microsoft Graph' -ScriptBlock {
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Certificate $Certificate -NoWelcome -ErrorAction Stop
        }

        # Verify connection
        $context = Get-MgContext
        if (-not $context) {
            throw "Graph connection completed but no context is available"
        }

        Write-AutopilotLog -Level Info -Message "Successfully connected to Microsoft Graph" -Phase 'GraphAuth' -Data @{
            TenantId  = $context.TenantId
            AuthType  = 'Certificate (App-Only)'
            Scopes    = ($context.Scopes -join ', ')
        }

        return $true
    }
    catch {
        throw "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    }
}
