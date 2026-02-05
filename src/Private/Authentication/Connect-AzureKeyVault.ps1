function Connect-AzureKeyVault {
    <#
    .SYNOPSIS
        Establishes a connection to Azure for Key Vault access.

    .DESCRIPTION
        Connects to Azure using device code flow authentication with Key Vault
        auth scope. Designed for OOBE scenarios where interactive browser-based
        authentication is not available.

        Disables WAM and LoginExperienceV2 which interfere with OOBE environments,
        and uses -AuthScope AzureKeyVaultServiceEndpointResourceId to ensure the
        token covers Key Vault data plane operations (not just ARM).

        Returns the Azure context object for use with -DefaultProfile.

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

    # Disable WAM broker and new login experience - required for OOBE environments
    # See: https://github.com/Azure/azure-powershell/issues/24962
    $env:AZURE_BROKER_ENABLED = '0'
    try {
        Update-AzConfig -EnableLoginByWam $false -LoginExperienceV2 'Off' -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }

    # Clear any stale context to prevent token cache issues
    Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null

    # Initiate device code flow with Key Vault auth scope
    Write-AutopilotLog -Level Info -Message "Initiating Azure device code authentication..." -Phase 'Authentication'
    Write-Host ""
    Write-Host "Azure authentication required for Key Vault access." -ForegroundColor Yellow
    Write-Host "Please follow the device code instructions below:" -ForegroundColor Yellow
    Write-Host ""

    $connectParams = @{
        UseDeviceAuthentication = $true
        AuthScope               = 'AzureKeyVaultServiceEndpointResourceId'
        ErrorAction             = 'Stop'
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
