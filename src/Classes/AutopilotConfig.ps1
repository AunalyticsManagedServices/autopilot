<#
.SYNOPSIS
    Configuration class for type-safe access to Autopilot settings.

.DESCRIPTION
    Provides a typed wrapper around the configuration hashtable
    for better IntelliSense support and validation.

.NOTES
    This class is optional - the hashtable-based config works fine.
    This provides better IDE support if desired.
#>
class AutopilotConfig {
    # Azure Key Vault settings
    [string]$KeyVaultName
    [string]$CertSecretName
    [string]$PasswordSecretName
    [string]$SubscriptionId

    # App Registration
    [string]$TenantId
    [string]$ClientId

    # Deployment settings
    [string]$Title
    [string]$AssignedUserExample
    [string]$AssignedComputerNameExample
    [string]$DefaultGroup
    [string[]]$GroupOptions
    [string]$DefaultGroupTag
    [string[]]$GroupTagOptions

    # Regional
    [string]$TimeZone

    # Behavior
    [bool]$CleanupExistingDevices
    [bool]$SkipGroupValidation
    [string]$PostAction
    [string]$Run
    [bool]$Assign
    [string]$DocsUrl

    # Retry policy
    [int]$MaxRetryAttempts
    [int]$InitialRetryDelayMs
    [double]$RetryBackoffMultiplier

    # Logging
    [bool]$EnableJsonLog
    [string]$LogLevel
    [string]$LogPath

    # Propagation delays (seconds)
    [int]$EntraCleanupDelay
    [int]$IntuneCleanupDelay
    [int]$AutopilotCleanupDelay

    # Constructor from hashtable
    AutopilotConfig([hashtable]$config) {
        # Key Vault
        $this.KeyVaultName = $config.KeyVault.Name
        $this.CertSecretName = $config.KeyVault.CertSecretName
        $this.PasswordSecretName = $config.KeyVault.PasswordSecretName
        $this.SubscriptionId = $config.KeyVault.SubscriptionId

        # App Registration
        $this.TenantId = $config.TenantId
        $this.ClientId = $config.ClientId

        # Deployment
        $this.Title = $config.Title
        $this.AssignedUserExample = $config.AssignedUserExample
        $this.AssignedComputerNameExample = $config.AssignedComputerNameExample
        $this.DefaultGroup = $config.DefaultGroup
        $this.GroupOptions = $config.GroupOptions
        $this.DefaultGroupTag = $config.DefaultGroupTag
        $this.GroupTagOptions = $config.GroupTagOptions

        # Regional
        $this.TimeZone = $config.TimeZone

        # Behavior
        $this.CleanupExistingDevices = $config.CleanupExistingDevices
        $this.SkipGroupValidation = $config.SkipGroupValidation
        $this.PostAction = $config.PostAction
        $this.Run = $config.Run
        $this.Assign = $config.Assign
        $this.DocsUrl = $config.DocsUrl

        # Retry policy
        $this.MaxRetryAttempts = $config.RetryPolicy.MaxAttempts
        $this.InitialRetryDelayMs = $config.RetryPolicy.InitialDelayMs
        $this.RetryBackoffMultiplier = $config.RetryPolicy.BackoffMultiplier

        # Logging
        $this.EnableJsonLog = $config.Logging.EnableJsonLog
        $this.LogLevel = $config.Logging.Level
        $this.LogPath = $config.Logging.Path

        # Propagation delays
        $this.EntraCleanupDelay = $config.PropagationDelays.EntraCleanup
        $this.IntuneCleanupDelay = $config.PropagationDelays.IntuneCleanup
        $this.AutopilotCleanupDelay = $config.PropagationDelays.AutopilotCleanup
    }

    # Convert back to hashtable for AutopilotOOBE parameters
    [hashtable]ToAutopilotOOBEParams() {
        return @{
            Title                       = $this.Title
            AssignedUserExample         = $this.AssignedUserExample
            AssignedComputerNameExample = $this.AssignedComputerNameExample
            AddToGroup                  = $this.DefaultGroup
            AddToGroupOptions           = $this.GroupOptions
            GroupTag                    = $this.DefaultGroupTag
            GroupTagOptions             = $this.GroupTagOptions
            PostAction                  = $this.PostAction
            Assign                      = $this.Assign
            Run                         = $this.Run
            Docs                        = $this.DocsUrl
        }
    }
}
