<#
.SYNOPSIS
    Result object for Autopilot deployment operations.

.DESCRIPTION
    Encapsulates the result of a deployment operation with success/failure status,
    messages, and any relevant data.
#>
class DeploymentResult {
    [bool]$Success
    [string]$Message
    [string]$Phase
    [datetime]$Timestamp
    [hashtable]$Data = @{}
    [System.Exception]$Error

    # Success constructor
    DeploymentResult([bool]$success, [string]$message) {
        $this.Success = $success
        $this.Message = $message
        $this.Timestamp = Get-Date
    }

    # Full constructor
    DeploymentResult([bool]$success, [string]$message, [string]$phase) {
        $this.Success = $success
        $this.Message = $message
        $this.Phase = $phase
        $this.Timestamp = Get-Date
    }

    # Constructor with data
    DeploymentResult([bool]$success, [string]$message, [string]$phase, [hashtable]$data) {
        $this.Success = $success
        $this.Message = $message
        $this.Phase = $phase
        $this.Data = $data
        $this.Timestamp = Get-Date
    }

    # Static factory methods
    static [DeploymentResult]Ok([string]$message) {
        return [DeploymentResult]::new($true, $message)
    }

    static [DeploymentResult]Ok([string]$message, [string]$phase) {
        return [DeploymentResult]::new($true, $message, $phase)
    }

    static [DeploymentResult]Ok([string]$message, [string]$phase, [hashtable]$data) {
        return [DeploymentResult]::new($true, $message, $phase, $data)
    }

    static [DeploymentResult]Fail([string]$message) {
        return [DeploymentResult]::new($false, $message)
    }

    static [DeploymentResult]Fail([string]$message, [string]$phase) {
        return [DeploymentResult]::new($false, $message, $phase)
    }

    static [DeploymentResult]Fail([string]$message, [System.Exception]$error) {
        $result = [DeploymentResult]::new($false, $message)
        $result.Error = $error
        return $result
    }

    static [DeploymentResult]Fail([string]$message, [string]$phase, [System.Exception]$error) {
        $result = [DeploymentResult]::new($false, $message, $phase)
        $result.Error = $error
        return $result
    }

    # Add data to the result
    [DeploymentResult]WithData([string]$key, [object]$value) {
        $this.Data[$key] = $value
        return $this
    }

    # Convert to string for display
    [string]ToString() {
        $status = if ($this.Success) { '[OK]' } else { '[FAIL]' }
        $phaseStr = if ($this.Phase) { "[$($this.Phase)] " } else { '' }
        return "$status $phaseStr$($this.Message)"
    }
}
