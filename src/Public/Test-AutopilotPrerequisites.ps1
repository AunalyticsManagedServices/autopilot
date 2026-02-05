function Test-AutopilotPrerequisites {
    <#
    .SYNOPSIS
        Tests all prerequisites for Autopilot deployment.

    .DESCRIPTION
        Performs comprehensive pre-flight checks without actually deploying:
        - Network connectivity
        - Required PowerShell modules
        - Azure authentication
        - Key Vault access
        - Certificate validity
        - Graph API connectivity
        - Entra group existence

        This is useful for validating a new setup before actual deployment.

    .PARAMETER ConfigPath
        Optional path to configuration file.

    .PARAMETER AutoFix
        Attempt to automatically fix issues (install modules, etc.).

    .OUTPUTS
        [PSCustomObject] with detailed results of all checks.

    .EXAMPLE
        $result = Test-AutopilotPrerequisites
        if ($result.AllPassed) { Write-Host "Ready to deploy!" }

    .EXAMPLE
        Test-AutopilotPrerequisites -AutoFix
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [switch]$AutoFix
    )

    Write-Host ""
    Write-Host "Autopilot Prerequisites Check" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host ""

    $results = [ordered]@{
        Configuration   = $null
        Network         = $null
        Modules         = $null
        AzureAuth       = $null
        KeyVault        = $null
        Certificate     = $null
        GraphConnection = $null
        Groups          = $null
    }

    $allPassed = $true

    # ==================== CONFIGURATION ====================
    Write-Host "1. Configuration" -ForegroundColor Yellow
    try {
        $config = Get-AutopilotConfig -ConfigPath $ConfigPath
        $script:Config = $config
        Write-Host "   [PASS] Configuration loaded successfully" -ForegroundColor Green
        $results.Configuration = @{ Status = 'Pass'; Details = 'Configuration loaded' }
    }
    catch {
        Write-Host "   [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        $results.Configuration = @{ Status = 'Fail'; Error = $_.Exception.Message }
        $allPassed = $false

        # Can't continue without config
        return [PSCustomObject]@{
            AllPassed = $false
            Results   = $results
        }
    }
    Write-Host ""

    # ==================== NETWORK ====================
    Write-Host "2. Network Connectivity" -ForegroundColor Yellow
    $networkOk = Test-NetworkConnectivity
    if ($networkOk) {
        $results.Network = @{ Status = 'Pass' }
    }
    else {
        $results.Network = @{ Status = 'Fail'; Error = 'One or more endpoints unreachable' }
        $allPassed = $false
    }
    Write-Host ""

    # ==================== MODULES ====================
    Write-Host "3. PowerShell Modules" -ForegroundColor Yellow
    $moduleResult = Test-RequiredModules -AutoInstall:$AutoFix
    if ($moduleResult.AllPresent) {
        $results.Modules = @{ Status = 'Pass'; Details = $moduleResult.ModuleStatus }
    }
    else {
        $results.Modules = @{ Status = 'Fail'; Details = $moduleResult.ModuleStatus }
        $allPassed = $false
    }
    Write-Host ""

    # Import modules for remaining checks
    try {
        Import-Module 'Az.Accounts' -Force -ErrorAction SilentlyContinue
        Import-Module 'Az.KeyVault' -Force -ErrorAction SilentlyContinue
        Import-Module 'Microsoft.Graph.Authentication' -Force -ErrorAction SilentlyContinue
        Import-Module 'Microsoft.Graph.Groups' -Force -ErrorAction SilentlyContinue
    }
    catch { }

    # ==================== AZURE AUTH ====================
    Write-Host "4. Azure Authentication" -ForegroundColor Yellow
    try {
        Connect-AzureKeyVault -SubscriptionId $config.KeyVault.SubscriptionId -TenantId $config.TenantId
        Write-Host "   [PASS] Azure authentication successful" -ForegroundColor Green
        $results.AzureAuth = @{ Status = 'Pass' }
    }
    catch {
        Write-Host "   [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        $results.AzureAuth = @{ Status = 'Fail'; Error = $_.Exception.Message }
        $allPassed = $false
    }
    Write-Host ""

    # ==================== KEY VAULT ====================
    Write-Host "5. Key Vault Access" -ForegroundColor Yellow
    if ($results.AzureAuth.Status -eq 'Pass') {
        try {
            # Test Key Vault access
            $secrets = Get-AzKeyVaultSecret -VaultName $config.KeyVault.Name -ErrorAction Stop | Select-Object -First 1
            Write-Host "   [PASS] Key Vault accessible: $($config.KeyVault.Name)" -ForegroundColor Green
            $results.KeyVault = @{ Status = 'Pass'; VaultName = $config.KeyVault.Name }
        }
        catch {
            Write-Host "   [FAIL] $($_.Exception.Message)" -ForegroundColor Red
            $results.KeyVault = @{ Status = 'Fail'; Error = $_.Exception.Message }
            $allPassed = $false
        }
    }
    else {
        Write-Host "   [SKIP] Azure authentication required" -ForegroundColor DarkGray
        $results.KeyVault = @{ Status = 'Skip'; Reason = 'Azure auth failed' }
    }
    Write-Host ""

    # ==================== CERTIFICATE ====================
    Write-Host "6. Certificate" -ForegroundColor Yellow
    if ($results.KeyVault.Status -eq 'Pass') {
        try {
            $cert = Get-CertificateFromKeyVault `
                -VaultName $config.KeyVault.Name `
                -CertSecretName $config.KeyVault.CertSecretName `
                -PasswordSecretName $config.KeyVault.PasswordSecretName

            $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
            if ($daysUntilExpiry -le 0) {
                Write-Host "   [FAIL] Certificate has expired" -ForegroundColor Red
                $results.Certificate = @{ Status = 'Fail'; Error = 'Certificate expired' }
                $allPassed = $false
            }
            elseif ($daysUntilExpiry -le 30) {
                Write-Host "   [WARN] Certificate expires in $daysUntilExpiry days" -ForegroundColor Yellow
                $results.Certificate = @{ Status = 'Warn'; DaysUntilExpiry = $daysUntilExpiry; Thumbprint = $cert.Thumbprint }
            }
            else {
                Write-Host "   [PASS] Certificate valid (expires in $daysUntilExpiry days)" -ForegroundColor Green
                $results.Certificate = @{ Status = 'Pass'; DaysUntilExpiry = $daysUntilExpiry; Thumbprint = $cert.Thumbprint }
            }
        }
        catch {
            Write-Host "   [FAIL] $($_.Exception.Message)" -ForegroundColor Red
            $results.Certificate = @{ Status = 'Fail'; Error = $_.Exception.Message }
            $allPassed = $false
        }
    }
    else {
        Write-Host "   [SKIP] Key Vault access required" -ForegroundColor DarkGray
        $results.Certificate = @{ Status = 'Skip'; Reason = 'Key Vault access failed' }
    }
    Write-Host ""

    # ==================== GRAPH CONNECTION ====================
    Write-Host "7. Microsoft Graph Connection" -ForegroundColor Yellow
    if ($results.Certificate.Status -eq 'Pass' -or $results.Certificate.Status -eq 'Warn') {
        try {
            Connect-GraphWithCertificate `
                -TenantId $config.TenantId `
                -ClientId $config.ClientId `
                -Certificate $cert

            Write-Host "   [PASS] Graph connection successful" -ForegroundColor Green
            $results.GraphConnection = @{ Status = 'Pass' }
        }
        catch {
            Write-Host "   [FAIL] $($_.Exception.Message)" -ForegroundColor Red
            $results.GraphConnection = @{ Status = 'Fail'; Error = $_.Exception.Message }
            $allPassed = $false
        }
    }
    else {
        Write-Host "   [SKIP] Certificate required" -ForegroundColor DarkGray
        $results.GraphConnection = @{ Status = 'Skip'; Reason = 'Certificate not available' }
    }
    Write-Host ""

    # ==================== GROUPS ====================
    Write-Host "8. Entra ID Groups" -ForegroundColor Yellow
    if ($results.GraphConnection.Status -eq 'Pass') {
        $groupsToValidate = $config.GroupOptions
        if ($groupsToValidate -and $groupsToValidate.Count -gt 0) {
            $groupsValid = Test-EntraGroupExists -GroupNames $groupsToValidate
            if ($groupsValid) {
                $results.Groups = @{ Status = 'Pass'; Groups = $groupsToValidate }
            }
            else {
                $results.Groups = @{ Status = 'Warn'; Groups = $groupsToValidate; Warning = 'Some groups not found' }
            }
        }
        else {
            Write-Host "   [SKIP] No groups configured" -ForegroundColor DarkGray
            $results.Groups = @{ Status = 'Skip'; Reason = 'No groups configured' }
        }
    }
    else {
        Write-Host "   [SKIP] Graph connection required" -ForegroundColor DarkGray
        $results.Groups = @{ Status = 'Skip'; Reason = 'Graph connection failed' }
    }
    Write-Host ""

    # ==================== SUMMARY ====================
    Write-Host "=============================" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "All prerequisites passed!" -ForegroundColor Green
        Write-Host "Ready to run: Start-AutopilotDeployment" -ForegroundColor White
    }
    else {
        Write-Host "Some prerequisites failed." -ForegroundColor Red
        Write-Host "Please resolve the issues above before deployment." -ForegroundColor White
    }
    Write-Host ""

    # Clean up
    $cert = $null
    [System.GC]::Collect()

    return [PSCustomObject]@{
        AllPassed = $allPassed
        Results   = $results
    }
}
