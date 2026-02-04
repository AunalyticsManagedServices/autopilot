@{
    # ============================================================================
    # AUNALYTICS AUTOPILOT DEPLOYMENT CONFIGURATION
    # ============================================================================
    # Secrets (certificate, password) are stored in Azure Key Vault.
    # This file contains only identifiers and settings - safe to commit.
    # ============================================================================

    # --------------------------------------------------------------------------
    # Azure Key Vault Configuration
    # --------------------------------------------------------------------------
    KeyVault                    = @{
        Name               = 'IITScriptKeyVault'
        CertSecretName     = 'AutopilotOOBE-Cert'
        PasswordSecretName = 'AutopilotOOBE-Cert-Password'
        SubscriptionId     = '48c75a95-95ae-4322-be88-dbf051049ea0'
    }

    # --------------------------------------------------------------------------
    # Entra App Registration
    # --------------------------------------------------------------------------
    TenantId                    = '34996142-c2c2-49f6-a30d-ccf73f568c9c'
    ClientId                    = 'bf98483c-c034-4338-802a-8bb0d84fb462'

    # --------------------------------------------------------------------------
    # Deployment Settings
    # --------------------------------------------------------------------------
    Title                       = 'Aunalytics Autopilot Registration'
    AssignedUserExample         = 'username@aunalytics.com'
    AssignedComputerNameExample = 'WAU####'

    DefaultGroup                = 'AzPC - ENR - Enterprise'
    GroupOptions                = @(
        'AzPC - ENR - Enterprise'
        # 'AzPC - ENR - Kiosk'    # Uncomment when group exists
        # 'AzPC - ENR - Shared'   # Uncomment when group exists
    )

    DefaultGroupTag             = 'Enterprise'
    GroupTagOptions             = @(
        'Enterprise'
    )

    # --------------------------------------------------------------------------
    # Regional Settings
    # --------------------------------------------------------------------------
    TimeZone                    = 'Eastern Standard Time'

    # --------------------------------------------------------------------------
    # Behavior Settings
    # --------------------------------------------------------------------------
    CleanupExistingDevices      = $true
    SkipGroupValidation         = $false
    PostAction                  = 'Restart'
    Run                         = 'WindowsSettings'
    Assign                      = $true
    DocsUrl                     = 'https://autopilotoobe.osdeploy.com/'

    # --------------------------------------------------------------------------
    # Retry Policy
    # --------------------------------------------------------------------------
    RetryPolicy                 = @{
        MaxAttempts       = 3
        InitialDelayMs    = 1000
        BackoffMultiplier = 2.0
    }

    # --------------------------------------------------------------------------
    # Logging Settings
    # --------------------------------------------------------------------------
    Logging                     = @{
        EnableJsonLog = $true
        Level         = 'Info'
    }

    # --------------------------------------------------------------------------
    # Propagation Delays (seconds)
    # --------------------------------------------------------------------------
    PropagationDelays           = @{
        EntraCleanup     = 15
        IntuneCleanup    = 10
        AutopilotCleanup = 10
    }
}
