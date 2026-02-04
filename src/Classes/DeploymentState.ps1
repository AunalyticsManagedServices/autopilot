# Deployment phase enumeration
enum DeploymentPhase {
    NotStarted
    PreFlightChecks
    ModuleInstallation
    AzureAuthentication
    KeyVaultAccess
    GraphAuthentication
    DeviceCleanup
    EntraCleanup
    IntuneCleanup
    AutopilotCleanup
    GroupValidation
    DeviceRegistration
    OOBELaunch
    Completed
    Failed
}

<#
.SYNOPSIS
    State machine for tracking Autopilot deployment progress.

.DESCRIPTION
    Provides checkpoint-based state tracking that enables:
    - Resume from partial failures
    - Skip already-completed phases
    - Track what was cleaned up
    - Prevent duplicate operations

.EXAMPLE
    $state = [DeploymentState]::new("$env:TEMP\autopilot-state.xml")
    $state.AdvanceTo([DeploymentPhase]::ModuleInstallation)
    if ($state.ShouldSkip([DeploymentPhase]::ModuleInstallation)) {
        Write-Host "Already completed module installation"
    }
#>
class DeploymentState {
    [DeploymentPhase]$CurrentPhase = [DeploymentPhase]::NotStarted
    [datetime]$StartedAt
    [datetime]$LastCheckpoint
    [hashtable]$PhaseResults = @{}
    [string]$StatePath
    [string]$DeviceSerial
    [string[]]$CleanedUpDeviceIds = @()
    [string]$LastError
    [bool]$IsResume = $false

    # Constructor
    DeploymentState([string]$path) {
        $this.StatePath = $path
        $this.StartedAt = Get-Date
        $this.LastCheckpoint = Get-Date
        $this.Load()
    }

    # Advance to a new phase
    [void]AdvanceTo([DeploymentPhase]$phase) {
        $this.CurrentPhase = $phase
        $this.LastCheckpoint = Get-Date
        $this.LastError = $null
        $this.Save()
    }

    # Record the result of a phase
    [void]RecordPhaseResult([DeploymentPhase]$phase, [object]$result) {
        $this.PhaseResults[$phase.ToString()] = @{
            Result      = $result
            CompletedAt = (Get-Date).ToString('o')
        }
        $this.Save()
    }

    # Record a cleaned up device ID
    [void]RecordCleanedDevice([string]$deviceId) {
        if ($deviceId -and $this.CleanedUpDeviceIds -notcontains $deviceId) {
            $this.CleanedUpDeviceIds += $deviceId
            $this.Save()
        }
    }

    # Check if a device was already cleaned up
    [bool]WasDeviceCleaned([string]$deviceId) {
        return $this.CleanedUpDeviceIds -contains $deviceId
    }

    # Record an error
    [void]RecordError([string]$error) {
        $this.LastError = $error
        $this.CurrentPhase = [DeploymentPhase]::Failed
        $this.Save()
    }

    # Mark as completed
    [void]MarkCompleted() {
        $this.CurrentPhase = [DeploymentPhase]::Completed
        $this.LastCheckpoint = Get-Date
        $this.Save()
    }

    # Save state to file
    [void]Save() {
        try {
            $this | Export-Clixml -Path $this.StatePath -Force
        }
        catch {
            # Silently fail - state persistence is nice to have, not critical
        }
    }

    # Load state from file
    [void]Load() {
        if (Test-Path $this.StatePath) {
            try {
                $saved = Import-Clixml -Path $this.StatePath

                # Only restore if it's from the same device and recent (within 24 hours)
                $currentSerial = try { (Get-CimInstance -ClassName Win32_BIOS).SerialNumber } catch { '' }

                if ($saved.DeviceSerial -eq $currentSerial) {
                    $age = (Get-Date) - $saved.LastCheckpoint
                    if ($age.TotalHours -lt 24) {
                        $this.CurrentPhase = $saved.CurrentPhase
                        $this.PhaseResults = $saved.PhaseResults
                        $this.CleanedUpDeviceIds = $saved.CleanedUpDeviceIds
                        $this.StartedAt = $saved.StartedAt
                        $this.IsResume = $true
                    }
                }
            }
            catch {
                # If we can't load, start fresh
                $this.IsResume = $false
            }
        }

        # Set device serial for future comparisons
        $this.DeviceSerial = try { (Get-CimInstance -ClassName Win32_BIOS).SerialNumber } catch { '' }
    }

    # Check if a phase should be skipped (already completed)
    [bool]ShouldSkip([DeploymentPhase]$phase) {
        # Can only skip if we're resuming and the current phase is past this one
        if (-not $this.IsResume) {
            return $false
        }

        return [int]$this.CurrentPhase -gt [int]$phase
    }

    # Get the result of a completed phase
    [object]GetPhaseResult([DeploymentPhase]$phase) {
        $key = $phase.ToString()
        if ($this.PhaseResults.ContainsKey($key)) {
            return $this.PhaseResults[$key].Result
        }
        return $null
    }

    # Reset state (for starting fresh)
    [void]Reset() {
        $this.CurrentPhase = [DeploymentPhase]::NotStarted
        $this.StartedAt = Get-Date
        $this.LastCheckpoint = Get-Date
        $this.PhaseResults = @{}
        $this.CleanedUpDeviceIds = @()
        $this.LastError = $null
        $this.IsResume = $false

        if (Test-Path $this.StatePath) {
            Remove-Item $this.StatePath -Force -ErrorAction SilentlyContinue
        }
    }

    # Get a summary of the state
    [string]GetSummary() {
        $completedPhases = $this.PhaseResults.Keys -join ', '
        return @"
Deployment State Summary:
  Current Phase: $($this.CurrentPhase)
  Started: $($this.StartedAt.ToString('o'))
  Last Checkpoint: $($this.LastCheckpoint.ToString('o'))
  Is Resume: $($this.IsResume)
  Completed Phases: $completedPhases
  Cleaned Devices: $($this.CleanedUpDeviceIds.Count)
  Last Error: $($this.LastError)
"@
    }
}
