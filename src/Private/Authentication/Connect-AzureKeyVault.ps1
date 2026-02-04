function Connect-AzureKeyVault {
    <#
    .SYNOPSIS
        Establishes a connection to Azure for Key Vault access.

    .DESCRIPTION
        Connects to Azure using device code flow authentication.
        This is designed for OOBE scenarios where interactive browser-based
        authentication may not be available.

        If already connected to Azure, validates the connection is still valid.

    .PARAMETER SubscriptionId
        Optional Azure subscription ID. If not specified, uses the default subscription.

    .OUTPUTS
        [bool] True if connected successfully, throws on failure.

    .EXAMPLE
        Connect-AzureKeyVault
        Connect-AzureKeyVault -SubscriptionId '00000000-0000-0000-0000-000000000000'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$SubscriptionId
    )

    Write-AutopilotLog -Level Info -Message "Establishing Azure connection for Key Vault access" -Phase 'Authentication'

    # Check if already connected
    $context = Get-AzContext -ErrorAction SilentlyContinue

    if ($context) {
        Write-AutopilotLog -Level Debug -Message "Existing Azure context found" -Phase 'Authentication' -Data @{
            Account      = $context.Account.Id
            Subscription = $context.Subscription.Name
            TenantId     = $context.Tenant.Id
        }

        # If subscription specified, ensure we're in the right one
        if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
            Write-AutopilotLog -Level Info -Message "Switching to specified subscription: $SubscriptionId" -Phase 'Authentication'
            try {
                Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Failed to switch to subscription '$SubscriptionId': $($_.Exception.Message)"
            }
        }

        return $true
    }

    # Not connected - initiate device code flow
    Write-AutopilotLog -Level Info -Message "Initiating Azure device code authentication..." -Phase 'Authentication'
    Write-Host ""
    Write-Host "Azure authentication required for Key Vault access." -ForegroundColor Yellow
    Write-Host "Please follow the device code instructions below:" -ForegroundColor Yellow
    Write-Host ""

    $connectParams = @{
        DeviceCode  = $true
        ErrorAction = 'Stop'
    }

    if ($SubscriptionId) {
        $connectParams['Subscription'] = $SubscriptionId
    }

    try {
        Connect-AzAccount @connectParams | Out-Null
    }
    catch {
        throw "Azure authentication failed: $($_.Exception.Message)"
    }

    # Verify connection
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        throw "Azure authentication completed but no context is available"
    }

    Write-AutopilotLog -Level Info -Message "Successfully connected to Azure" -Phase 'Authentication' -Data @{
        Account      = $context.Account.Id
        Subscription = $context.Subscription.Name
        TenantId     = $context.Tenant.Id
    }

    return $true
}
