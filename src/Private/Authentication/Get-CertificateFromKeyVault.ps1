function Get-CertificateFromKeyVault {
    <#
    .SYNOPSIS
        Retrieves a certificate from Azure Key Vault.

    .DESCRIPTION
        Retrieves a Base64-encoded PFX certificate and its password from Azure Key Vault,
        then creates an X509Certificate2 object for use with Microsoft Graph authentication.

        The certificate is stored in Key Vault as a secret (Base64-encoded PFX)
        with its password in a separate secret.

    .PARAMETER VaultName
        The name of the Azure Key Vault.

    .PARAMETER CertSecretName
        The name of the secret containing the Base64-encoded PFX certificate.

    .PARAMETER PasswordSecretName
        The name of the secret containing the PFX password.
        Defaults to '{CertSecretName}-Password'.

    .PARAMETER AzureContext
        Azure context object from Connect-AzureKeyVault. Used with -DefaultProfile
        to bypass token cache issues during OOBE.

    .OUTPUTS
        [System.Security.Cryptography.X509Certificates.X509Certificate2]

    .EXAMPLE
        $cert = Get-CertificateFromKeyVault -VaultName 'my-keyvault' -CertSecretName 'AutopilotOOBE-Cert'

    .NOTES
        Requires Az.KeyVault module and an active Azure connection.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,

        [Parameter(Mandatory)]
        [string]$CertSecretName,

        [Parameter()]
        [string]$PasswordSecretName,

        [Parameter()]
        [object]$AzureContext
    )

    # Default password secret name
    if (-not $PasswordSecretName) {
        $PasswordSecretName = "$CertSecretName-Password"
    }

    Write-AutopilotLog -Level Info -Message "Retrieving certificate from Key Vault: $VaultName" -Phase 'Authentication' -Data @{
        VaultName      = $VaultName
        CertSecret     = $CertSecretName
        PasswordSecret = $PasswordSecretName
    }

    # Build common params for Key Vault calls
    $kvParams = @{ ErrorAction = 'Stop' }
    if ($AzureContext) {
        $kvParams['DefaultProfile'] = $AzureContext
        Write-AutopilotLog -Level Debug -Message "Using explicit Azure context: $($AzureContext.Account.Id)" -Phase 'Authentication'
    }

    # Retrieve the Base64-encoded PFX
    $certSecret = Invoke-WithRetry -OperationName 'Get certificate secret' -ScriptBlock {
        Get-AzKeyVaultSecret -VaultName $VaultName -Name $CertSecretName -AsPlainText @kvParams
    }

    if (-not $certSecret) {
        throw "Certificate secret '$CertSecretName' not found in Key Vault '$VaultName'"
    }

    Write-AutopilotLog -Level Debug -Message "Certificate secret retrieved successfully" -Phase 'Authentication'

    # Retrieve the password
    $passwordSecret = Invoke-WithRetry -OperationName 'Get password secret' -ScriptBlock {
        Get-AzKeyVaultSecret -VaultName $VaultName -Name $PasswordSecretName -AsPlainText @kvParams
    }

    if (-not $passwordSecret) {
        throw "Password secret '$PasswordSecretName' not found in Key Vault '$VaultName'"
    }

    Write-AutopilotLog -Level Debug -Message "Password secret retrieved successfully" -Phase 'Authentication'

    # Convert to certificate object
    try {
        $pfxBytes = [System.Convert]::FromBase64String($certSecret)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfxBytes,
            $passwordSecret,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }
    catch {
        throw "Failed to create certificate from Key Vault secrets: $($_.Exception.Message)"
    }

    # Validate certificate
    if (-not $cert.HasPrivateKey) {
        throw "Certificate does not have a private key. Ensure the PFX was exported with the private key."
    }

    $now = Get-Date
    if ($cert.NotBefore -gt $now) {
        throw "Certificate is not yet valid. NotBefore: $($cert.NotBefore)"
    }

    if ($cert.NotAfter -lt $now) {
        throw "Certificate has expired. NotAfter: $($cert.NotAfter)"
    }

    # Warn if certificate is expiring soon (within 30 days)
    $daysUntilExpiry = ($cert.NotAfter - $now).Days
    if ($daysUntilExpiry -le 30) {
        Write-AutopilotLog -Level Warning -Message "Certificate expires in $daysUntilExpiry days!" -Phase 'Authentication' -Data @{
            Thumbprint = $cert.Thumbprint
            Expires    = $cert.NotAfter.ToString('o')
        }
    }

    Write-AutopilotLog -Level Info -Message "Certificate loaded successfully" -Phase 'Authentication' -Data @{
        Subject         = $cert.Subject
        Thumbprint      = $cert.Thumbprint
        Expires         = $cert.NotAfter.ToString('o')
        DaysUntilExpiry = $daysUntilExpiry
    }

    # Clear secrets from memory
    $certSecret = $null
    $passwordSecret = $null
    $pfxBytes = $null

    return $cert
}
