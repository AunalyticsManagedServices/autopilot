function Test-EntraGroupExists {
    <#
    .SYNOPSIS
        Validates that specified Entra ID groups exist.

    .DESCRIPTION
        Checks that the given group names exist in Entra ID.
        This helps prevent deployment failures due to typos in group names.

    .PARAMETER GroupNames
        Array of group names to validate.

    .OUTPUTS
        [bool] True if all groups exist.

    .EXAMPLE
        if (Test-EntraGroupExists -GroupNames @('Group1', 'Group2')) { ... }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string[]]$GroupNames
    )

    # Ensure we have a Graph connection
    if (-not (Test-GraphConnection)) {
        Write-AutopilotLog -Level Warning -Message "No Graph connection - skipping group validation" -Phase 'Validation'
        return $true  # Don't fail if we can't validate
    }

    Write-AutopilotLog -Level Info -Message "Validating Entra ID groups" -Phase 'Validation'
    Write-Host "Validating Entra ID groups:" -ForegroundColor Yellow

    $allExist = $true
    $missingGroups = @()

    foreach ($groupName in $GroupNames) {
        if ([string]::IsNullOrWhiteSpace($groupName)) {
            continue
        }

        try {
            $group = Invoke-WithRetry -OperationName "Validate group '$groupName'" -ScriptBlock {
                Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
            }

            if ($group) {
                Write-AutopilotLog -Level Debug -Message "Group found: $groupName" -Phase 'Validation' -Data @{
                    GroupId = $group.Id
                }
                Write-Host "  [OK] $groupName" -ForegroundColor Green
            }
            else {
                Write-AutopilotLog -Level Warning -Message "Group not found: $groupName" -Phase 'Validation'
                Write-Host "  [MISSING] $groupName" -ForegroundColor Red
                $missingGroups += $groupName
                $allExist = $false
            }
        }
        catch {
            Write-AutopilotLog -Level Warning -Message "Error validating group: $groupName" -Phase 'Validation' -Data @{
                Error = $_.Exception.Message
            }
            Write-Host "  [ERROR] $groupName - $($_.Exception.Message)" -ForegroundColor Red
            $missingGroups += $groupName
            $allExist = $false
        }
    }

    if (-not $allExist) {
        Write-Host ""
        Write-Host "WARNING: Some groups were not found in Entra ID:" -ForegroundColor Yellow
        foreach ($missing in $missingGroups) {
            Write-Host "  - $missing" -ForegroundColor White
        }
    }

    return $allExist
}
