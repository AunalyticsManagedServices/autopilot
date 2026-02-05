function Connect-AzureKeyVault {
    <#
    .SYNOPSIS
        Establishes a connection to Azure for Key Vault access.

    .DESCRIPTION
        Connects to Azure using device code flow authentication.
        This is designed for OOBE scenarios where interactive browser-based
        authentication may not be available.

        Returns the Azure context object for use with -DefaultProfile on
        subsequent Az cmdlets, bypassing token cache issues during OOBE.

    .PARAMETER SubscriptionId
        Optional Azure subscription ID. If not specified, uses the default subscription.

    .PARAMETER TenantId
        Optional Azure tenant ID. Ensures device code auth targets the correct tenant.

    .OUTPUTS
        [Microsoft.Azure.Commands.Profile.Models.Core.PSAzureContext]

    .EXAMPLE
        $ctx = Connect-AzureKeyVault -SubscriptionId '...' -TenantId '...'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$TenantId
    )

    Write-AutopilotLog -Level Info -Message "Establishing Azure connection for Key Vault access" -Phase 'Authentication'

    # Disable WAM broker to prevent token cache issues during OOBE
    $env:AZURE_BROKER_ENABLED = '0'
    try {
        Update-AzConfig -EnableLoginByWam $false -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }

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
                $context = (Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop)
            }
            catch {
                throw "Failed to switch to subscription '$SubscriptionId': $($_.Exception.Message)"
            }
        }

        return $context
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

    if ($TenantId) {
        $connectParams['Tenant'] = $TenantId
    }

    if ($SubscriptionId) {
        $connectParams['Subscription'] = $SubscriptionId
    }

    try {
        $connectResult = Connect-AzAccount @connectParams
        $context = $connectResult.Context
    }
    catch {
        throw "Azure authentication failed: $($_.Exception.Message)"
    }

    if (-not $context) {
        throw "Azure authentication completed but no context is available"
    }

    Write-AutopilotLog -Level Info -Message "Successfully connected to Azure" -Phase 'Authentication' -Data @{
        Account      = $context.Account.Id
        Subscription = $context.Subscription.Name
        TenantId     = $context.Tenant.Id
    }

    return $context
}
