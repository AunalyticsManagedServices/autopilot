function Get-AutopilotConfig {
    <#
    .SYNOPSIS
        Loads and returns the Autopilot deployment configuration.

    .DESCRIPTION
        Loads configuration from a PSD1 file and merges with defaults.
        Supports configuration file in multiple locations:
        1. Explicit path via -ConfigPath parameter
        2. config/autopilot.config.psd1 relative to module
        3. $env:AUTOPILOT_CONFIG_PATH environment variable

    .PARAMETER ConfigPath
        Optional explicit path to the configuration file.

    .OUTPUTS
        [hashtable] The merged configuration.

    .EXAMPLE
        $config = Get-AutopilotConfig
        $config = Get-AutopilotConfig -ConfigPath 'C:\Config\custom.psd1'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ConfigPath
    )

    # Return cached config if available
    if ($script:Config -and -not $ConfigPath) {
        return $script:Config
    }

    # Determine config file location
    $configLocations = @()

    if ($ConfigPath) {
        $configLocations += $ConfigPath
    }

    # Check environment variable
    if ($env:AUTOPILOT_CONFIG_PATH) {
        $configLocations += $env:AUTOPILOT_CONFIG_PATH
    }

    # Check relative to module root
    $moduleRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
    $configLocations += Join-Path -Path $moduleRoot -ChildPath '..\config\autopilot.config.psd1'
    $configLocations += Join-Path -Path $moduleRoot -ChildPath 'config\autopilot.config.psd1'

    # Find first existing config file
    $foundConfig = $null
    foreach ($location in $configLocations) {
        if ($location -and (Test-Path -Path $location -ErrorAction SilentlyContinue)) {
            $foundConfig = (Resolve-Path -Path $location).Path
            break
        }
    }

    if (-not $foundConfig) {
        throw "Configuration file not found. Please create config/autopilot.config.psd1 or set AUTOPILOT_CONFIG_PATH environment variable. See config/autopilot.config.sample.psd1 for reference."
    }

    Write-AutopilotLog -Level Info -Message "Loading configuration from: $foundConfig" -Phase 'Configuration'

    # Load configuration file
    try {
        $loadedConfig = Import-PowerShellDataFile -Path $foundConfig -ErrorAction Stop
    }
    catch {
        throw "Failed to load configuration file '$foundConfig': $($_.Exception.Message)"
    }

    # Merge with defaults
    $mergedConfig = Merge-ConfigWithDefaults -Config $loadedConfig

    # Validate configuration
    $validationResult = Test-ConfigValidation -Config $mergedConfig
    if (-not $validationResult.IsValid) {
        $errorMessages = $validationResult.Errors -join "`n  - "
        throw "Configuration validation failed:`n  - $errorMessages"
    }

    # Cache the configuration
    $script:Config = $mergedConfig

    return $mergedConfig
}
