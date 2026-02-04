function Write-AutopilotLog {
    <#
    .SYNOPSIS
        Writes structured log entries for Autopilot deployment.

    .DESCRIPTION
        Provides consistent logging throughout the module with:
        - Colored console output for readability
        - Structured JSON log files for analysis and troubleshooting
        - Configurable log levels
        - Optional additional data for context

    .PARAMETER Level
        The log level: Debug, Info, Warning, or Error.

    .PARAMETER Message
        The log message.

    .PARAMETER Phase
        The deployment phase (e.g., 'Authentication', 'DeviceCleanup', 'Enrollment').

    .PARAMETER Data
        Optional hashtable of additional data to include in the log entry.

    .EXAMPLE
        Write-AutopilotLog -Level Info -Message "Starting deployment"
        Write-AutopilotLog -Level Warning -Message "Device already exists" -Phase 'DeviceCleanup' -Data @{ DeviceId = 'abc123' }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Phase,

        [Parameter()]
        [hashtable]$Data
    )

    # Get config settings
    $config = $script:Config
    $configLevel = if ($config.Logging.Level) { $config.Logging.Level } else { 'Info' }
    $enableJson = if ($null -ne $config.Logging.EnableJsonLog) { $config.Logging.EnableJsonLog } else { $true }

    # Log level filtering
    $levelOrder = @{
        'Debug'   = 0
        'Info'    = 1
        'Warning' = 2
        'Error'   = 3
    }

    if ($levelOrder[$Level] -lt $levelOrder[$configLevel]) {
        return
    }

    # Build log entry
    $timestamp = Get-Date -Format 'o'
    $entry = [ordered]@{
        Timestamp = $timestamp
        Level     = $Level
        Message   = $Message
    }

    if ($Phase) {
        $entry.Phase = $Phase
    }

    # Add device serial if available
    if ($script:DeviceIdentifiers) {
        $entry.Device = $script:DeviceIdentifiers.SerialNumber
    }

    if ($Data) {
        $entry.Data = $Data
    }

    # Console output with colors
    $levelColors = @{
        'Debug'   = 'DarkGray'
        'Info'    = 'White'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }

    $color = $levelColors[$Level]
    $prefix = "[$($timestamp.Substring(11, 8))]"
    $levelTag = "[$Level]".PadRight(9)

    if ($Phase) {
        $phaseTag = "[$Phase]"
        Write-Host "$prefix $levelTag $phaseTag $Message" -ForegroundColor $color
    }
    else {
        Write-Host "$prefix $levelTag $Message" -ForegroundColor $color
    }

    # JSON log file
    if ($enableJson) {
        $logPath = $script:LogPath
        if (-not $logPath) {
            $logPath = if ($config.Logging.Path) {
                $config.Logging.Path
            }
            else {
                Join-Path $env:TEMP "Autopilot-$(Get-Date -Format 'yyyyMMdd').json"
            }
            $script:LogPath = $logPath
        }

        try {
            $jsonLine = $entry | ConvertTo-Json -Compress -Depth 5
            Add-Content -Path $logPath -Value $jsonLine -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail - logging shouldn't break the deployment
        }
    }
}
