@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'Autopilot.psm1'

    # Version number of this module.
    ModuleVersion = '6.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a7b8c9d0-1234-5678-9abc-def012345678'

    # Author of this module
    Author = 'Aunalytics'

    # Company or vendor of this module
    CompanyName = 'Aunalytics'

    # Copyright statement for this module
    Copyright = '(c) Aunalytics. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Windows Autopilot OOBE deployment module with Azure Key Vault integration, retry logic, and structured logging.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' },
        @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.0.0' },
        @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.0.0' },
        @{ ModuleName = 'Microsoft.Graph.DeviceManagement.Enrollment'; ModuleVersion = '2.0.0' },
        @{ ModuleName = 'Microsoft.Graph.DeviceManagement'; ModuleVersion = '2.0.0' }
    )

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry
    FunctionsToExport = @(
        'Start-AutopilotDeployment',
        'Test-AutopilotPrerequisites',
        'Get-AutopilotStatus'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for module discovery
            Tags = @('Autopilot', 'OOBE', 'Windows', 'Deployment', 'Intune', 'Entra')

            # A URL to the license for this module.
            LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = ''

            # A URL to an icon representing this module.
            IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
## 6.0.0
- Complete architectural redesign as proper PowerShell module
- Azure Key Vault integration for secure credential management
- Retry logic with exponential backoff for transient failures
- Structured JSON logging for troubleshooting
- State machine for resumable deployments
- Cached device identifiers (single WMI query)
- Comprehensive Pester test suite
'@

            # Prerelease string of this module
            Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false

            # External dependent modules of this module
            ExternalModuleDependencies = @(
                'Az.Accounts',
                'Az.KeyVault',
                'AutopilotOOBE',
                'PSWriteColor'
            )
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    DefaultCommandPrefix = ''
}
