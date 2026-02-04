function Get-AutopilotStatus {
    <#
    .SYNOPSIS
        Gets the current status of Autopilot deployment.

    .DESCRIPTION
        Returns information about:
        - Current deployment state (if any)
        - Device information
        - Configuration status
        - Module status

    .PARAMETER ConfigPath
        Optional path to configuration file.

    .OUTPUTS
        [PSCustomObject] with status information.

    .EXAMPLE
        Get-AutopilotStatus

    .EXAMPLE
        $status = Get-AutopilotStatus
        Write-Host "Current phase: $($status.DeploymentState.CurrentPhase)"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath
    )

    Write-Host ""
    Write-Host "Autopilot Deployment Status" -ForegroundColor Cyan
    Write-Host "===========================" -ForegroundColor Cyan
    Write-Host ""

    $status = [ordered]@{
        Timestamp       = Get-Date
        DeviceInfo      = $null
        DeploymentState = $null
        Configuration   = $null
        GraphConnection = $null
    }

    # ==================== DEVICE INFO ====================
    Write-Host "Device Information:" -ForegroundColor Yellow
    try {
        $deviceInfo = Get-DeviceIdentifiers
        Write-Host "  Computer Name: $($deviceInfo.ComputerName)" -ForegroundColor White
        Write-Host "  Serial Number: $($deviceInfo.SerialNumber)" -ForegroundColor White
        Write-Host "  Manufacturer:  $($deviceInfo.Manufacturer)" -ForegroundColor White
        Write-Host "  Model:         $($deviceInfo.Model)" -ForegroundColor White
        $status.DeviceInfo = $deviceInfo
    }
    catch {
        Write-Host "  [ERROR] Could not retrieve device info: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""

    # ==================== DEPLOYMENT STATE ====================
    Write-Host "Deployment State:" -ForegroundColor Yellow
    $statePath = Join-Path $env:TEMP 'Autopilot-DeploymentState.xml'
    if (Test-Path $statePath) {
        try {
            $state = [DeploymentState]::new($statePath)
            Write-Host "  Current Phase:   $($state.CurrentPhase)" -ForegroundColor White
            Write-Host "  Started:         $($state.StartedAt)" -ForegroundColor White
            Write-Host "  Last Checkpoint: $($state.LastCheckpoint)" -ForegroundColor White
            Write-Host "  Is Resume:       $($state.IsResume)" -ForegroundColor White

            if ($state.LastError) {
                Write-Host "  Last Error:      $($state.LastError)" -ForegroundColor Red
            }

            $completedCount = $state.PhaseResults.Keys.Count
            Write-Host "  Completed Phases: $completedCount" -ForegroundColor White

            $status.DeploymentState = @{
                CurrentPhase    = $state.CurrentPhase.ToString()
                StartedAt       = $state.StartedAt
                LastCheckpoint  = $state.LastCheckpoint
                IsResume        = $state.IsResume
                LastError       = $state.LastError
                CompletedPhases = $state.PhaseResults.Keys
            }
        }
        catch {
            Write-Host "  [ERROR] Could not read state file" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  No active deployment (state file not found)" -ForegroundColor DarkGray
        $status.DeploymentState = $null
    }
    Write-Host ""

    # ==================== CONFIGURATION ====================
    Write-Host "Configuration:" -ForegroundColor Yellow
    try {
        $config = Get-AutopilotConfig -ConfigPath $ConfigPath
        Write-Host "  Tenant ID:    $($config.TenantId)" -ForegroundColor White
        Write-Host "  Client ID:    $($config.ClientId)" -ForegroundColor White
        Write-Host "  Key Vault:    $($config.KeyVault.Name)" -ForegroundColor White
        Write-Host "  Default Group: $($config.DefaultGroup)" -ForegroundColor White
        Write-Host "  Time Zone:    $($config.TimeZone)" -ForegroundColor White
        $status.Configuration = @{
            TenantId    = $config.TenantId
            ClientId    = $config.ClientId
            KeyVault    = $config.KeyVault.Name
            DefaultGroup = $config.DefaultGroup
            TimeZone    = $config.TimeZone
        }
    }
    catch {
        Write-Host "  [ERROR] Could not load configuration: $($_.Exception.Message)" -ForegroundColor Red
        $status.Configuration = $null
    }
    Write-Host ""

    # ==================== GRAPH CONNECTION ====================
    Write-Host "Graph Connection:" -ForegroundColor Yellow
    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Host "  Status:   Connected" -ForegroundColor Green
            Write-Host "  Tenant:   $($context.TenantId)" -ForegroundColor White
            Write-Host "  Auth:     $($context.AuthType)" -ForegroundColor White
            $status.GraphConnection = @{
                Connected = $true
                TenantId  = $context.TenantId
                AuthType  = $context.AuthType
            }
        }
        else {
            Write-Host "  Status:   Not connected" -ForegroundColor DarkGray
            $status.GraphConnection = @{ Connected = $false }
        }
    }
    catch {
        Write-Host "  Status:   Unknown" -ForegroundColor DarkGray
        $status.GraphConnection = @{ Connected = $false }
    }
    Write-Host ""

    # ==================== LOG FILES ====================
    Write-Host "Recent Log Files:" -ForegroundColor Yellow
    $logFiles = Get-ChildItem -Path $env:TEMP -Filter 'Autopilot*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5

    if ($logFiles) {
        foreach ($log in $logFiles) {
            Write-Host "  $($log.Name) - $($log.LastWriteTime)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  No log files found" -ForegroundColor DarkGray
    }
    Write-Host ""

    return [PSCustomObject]$status
}
