function Test-RequiredModules {
    <#
    .SYNOPSIS
        Tests if required PowerShell modules are installed.

    .DESCRIPTION
        Checks for the presence of required modules and optionally installs
        missing ones. Returns detailed information about module status.

    .PARAMETER Modules
        Array of module specifications with Name and optional MinimumVersion.

    .PARAMETER AutoInstall
        If specified, automatically install missing modules.

    .OUTPUTS
        [PSCustomObject] with AllPresent (bool) and ModuleStatus (array) properties.

    .EXAMPLE
        $result = Test-RequiredModules -AutoInstall
        if ($result.AllPresent) { Write-Host "All modules installed" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable[]]$Modules,

        [Parameter()]
        [switch]$AutoInstall
    )

    # Default modules if not specified
    if (-not $Modules) {
        $Modules = @(
            @{ Name = 'Microsoft.Graph.Authentication'; MinimumVersion = '2.0.0' },
            @{ Name = 'Microsoft.Graph.Groups'; MinimumVersion = '2.0.0' },
            @{ Name = 'Microsoft.Graph.Identity.DirectoryManagement'; MinimumVersion = '2.0.0' },
            @{ Name = 'Microsoft.Graph.DeviceManagement.Enrollment'; MinimumVersion = '2.0.0' },
            @{ Name = 'Microsoft.Graph.DeviceManagement'; MinimumVersion = '2.0.0' },
            @{ Name = 'Az.Accounts'; MinimumVersion = '2.0.0' },
            @{ Name = 'Az.KeyVault'; MinimumVersion = '4.0.0' },
            @{ Name = 'AutopilotOOBE'; MinimumVersion = '24.1.29' },
            @{ Name = 'PSWriteColor' }
        )
    }

    Write-AutopilotLog -Level Info -Message "Checking required PowerShell modules" -Phase 'PreFlight'
    Write-Host "Checking required PowerShell modules:" -ForegroundColor White

    $allPresent = $true
    $moduleStatus = @()

    foreach ($module in $Modules) {
        $name = $module.Name
        $minVersion = $module.MinimumVersion

        $installed = Get-Module -Name $name -ListAvailable | Where-Object {
            -not $minVersion -or $_.Version -ge [version]$minVersion
        } | Select-Object -First 1

        if ($installed) {
            $status = [PSCustomObject]@{
                Name             = $name
                RequiredVersion  = $minVersion
                InstalledVersion = $installed.Version.ToString()
                Status           = 'Installed'
            }
            $versionStr = if ($minVersion) { "v$($installed.Version) (>= $minVersion)" } else { "v$($installed.Version)" }
            Write-Host "  [OK] $name $versionStr" -ForegroundColor Green
        }
        else {
            if ($AutoInstall) {
                try {
                    Write-Host "  [INSTALL] $name..." -ForegroundColor Yellow -NoNewline
                    $installParams = @{
                        Name        = $name
                        Force       = $true
                        ErrorAction = 'Stop'
                    }
                    if ($minVersion) {
                        $installParams['MinimumVersion'] = $minVersion
                    }
                    Install-Module @installParams
                    Write-Host " OK" -ForegroundColor Green

                    $status = [PSCustomObject]@{
                        Name             = $name
                        RequiredVersion  = $minVersion
                        InstalledVersion = (Get-Module -Name $name -ListAvailable | Select-Object -First 1).Version.ToString()
                        Status           = 'Installed'
                    }
                }
                catch {
                    Write-Host " FAILED" -ForegroundColor Red
                    $status = [PSCustomObject]@{
                        Name             = $name
                        RequiredVersion  = $minVersion
                        InstalledVersion = $null
                        Status           = 'Failed'
                        Error            = $_.Exception.Message
                    }
                    $allPresent = $false
                }
            }
            else {
                $versionStr = if ($minVersion) { " (requires >= $minVersion)" } else { '' }
                Write-Host "  [MISSING] $name$versionStr" -ForegroundColor Red
                $status = [PSCustomObject]@{
                    Name             = $name
                    RequiredVersion  = $minVersion
                    InstalledVersion = $null
                    Status           = 'Missing'
                }
                $allPresent = $false
            }
        }

        $moduleStatus += $status
    }

    Write-AutopilotLog -Level Info -Message "Module check completed" -Phase 'PreFlight' -Data @{
        AllPresent   = $allPresent
        TotalModules = $Modules.Count
        Missing      = ($moduleStatus | Where-Object Status -ne 'Installed').Count
    }

    return [PSCustomObject]@{
        AllPresent   = $allPresent
        ModuleStatus = $moduleStatus
    }
}
