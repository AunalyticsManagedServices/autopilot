function Set-WAMState {
    <#
    .SYNOPSIS
        Enables or disables Web Account Manager (WAM) via registry settings.

    .DESCRIPTION
        WAM (Web Account Manager) prompts users to choose between "Personal"
        or "Work/School" accounts during authentication. During OOBE, this
        interferes with automated deployment.

        This function disables WAM by setting registry keys, allowing
        unattended authentication flows.

    .PARAMETER Enabled
        Set to $true to enable WAM (normal operation), $false to disable.

    .OUTPUTS
        [void]

    .EXAMPLE
        Set-WAMState -Enabled $false  # Disable WAM for unattended operation
        Set-WAMState -Enabled $true   # Re-enable WAM after deployment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}',
        'HKLM:\SOFTWARE\Microsoft\IdentityStore\LoadParameters\{B16898C6-A148-4967-9171-64D755DA8520}',
        'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount'
    )

    $value = if ($Enabled) { 1 } else { 0 }
    $action = if ($Enabled) { 'Enabling' } else { 'Disabling' }

    Write-AutopilotLog -Level Debug -Message "$action Web Account Manager (WAM)" -Phase 'WAM'

    foreach ($path in $regPaths) {
        try {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -Path $path -Name 'Enabled' -Value $value -Type DWord -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-AutopilotLog -Level Debug -Message "Failed to set WAM registry at $path" -Phase 'WAM' -Data @{
                Error = $_.Exception.Message
            }
        }
    }

    Write-AutopilotLog -Level Info -Message "WAM $($action.ToLower()) complete" -Phase 'WAM'
}
