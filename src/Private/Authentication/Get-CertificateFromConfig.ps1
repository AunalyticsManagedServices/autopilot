function Get-CertificateFromConfig {
    <#
    .SYNOPSIS
        Retrieves the authentication certificate based on configuration.

    .DESCRIPTION
        Loads the certificate from Azure Key Vault using the configuration settings.
        Handles the full flow of:
        1. Connecting to Azure (device code flow)
        2. Retrieving certificate from Key Vault
        3. Creating X509Certificate2 object

    .PARAMETER Config
        The Autopilot configuration hashtable. If not provided, loads from Get-AutopilotConfig.

    .OUTPUTS
        [System.Security.Cryptography.X509Certificates.X509Certificate2]

    .EXAMPLE
        $cert = Get-CertificateFromConfig
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter()]
        [hashtable]$Config
    )

    if (-not $Config) {
        $Config = Get-AutopilotConfig
    }

    Write-AutopilotLog -Level Info -Message "Retrieving authentication certificate" -Phase 'Authentication'

    # Ensure we have Key Vault configuration
    if (-not $Config.KeyVault -or -not $Config.KeyVault.Name) {
        throw "Key Vault configuration is required. Please configure KeyVault.Name in your config file."
    }

    # Connect to Azure for Key Vault access
    $subscriptionId = $Config.KeyVault.SubscriptionId
    $azContext = Connect-AzureKeyVault -SubscriptionId $subscriptionId -TenantId $Config.TenantId

    # Retrieve certificate from Key Vault
    $cert = Get-CertificateFromKeyVault `
        -VaultName $Config.KeyVault.Name `
        -CertSecretName $Config.KeyVault.CertSecretName `
        -PasswordSecretName $Config.KeyVault.PasswordSecretName `
        -AzureContext $azContext

    return $cert
}
