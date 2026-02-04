function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with retry logic and exponential backoff.

    .DESCRIPTION
        Wraps any operation with configurable retry behavior for handling transient failures.
        Uses exponential backoff to avoid overwhelming services during outages.

        Retries are triggered for:
        - Network-related errors (timeout, connection)
        - HTTP 429 (Too Many Requests)
        - HTTP 503/504 (Service Unavailable/Gateway Timeout)
        - Throttling errors

    .PARAMETER ScriptBlock
        The script block to execute.

    .PARAMETER OperationName
        A friendly name for the operation (used in logging).

    .PARAMETER MaxAttempts
        Maximum number of attempts before giving up. Default: 3

    .PARAMETER InitialDelayMs
        Initial delay in milliseconds before first retry. Default: 1000

    .PARAMETER BackoffMultiplier
        Multiplier for exponential backoff. Default: 2.0
        Delay = InitialDelay * (BackoffMultiplier ^ attemptNumber)

    .PARAMETER RetryableErrorPatterns
        Array of regex patterns that identify retryable errors.

    .OUTPUTS
        The output of the script block if successful.

    .EXAMPLE
        $result = Invoke-WithRetry -OperationName 'Get devices' -ScriptBlock {
            Get-MgDevice -Filter "displayName eq 'PC001'"
        }

    .EXAMPLE
        $result = Invoke-WithRetry -ScriptBlock { Invoke-RestMethod -Uri $url } -MaxAttempts 5
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [string]$OperationName = 'Operation',

        [Parameter()]
        [int]$MaxAttempts,

        [Parameter()]
        [int]$InitialDelayMs,

        [Parameter()]
        [double]$BackoffMultiplier,

        [Parameter()]
        [string[]]$RetryableErrorPatterns
    )

    # Get retry settings from config or use defaults
    $config = $script:Config
    if (-not $MaxAttempts) {
        $MaxAttempts = if ($config.RetryPolicy.MaxAttempts) { $config.RetryPolicy.MaxAttempts } else { 3 }
    }
    if (-not $InitialDelayMs) {
        $InitialDelayMs = if ($config.RetryPolicy.InitialDelayMs) { $config.RetryPolicy.InitialDelayMs } else { 1000 }
    }
    if (-not $BackoffMultiplier) {
        $BackoffMultiplier = if ($config.RetryPolicy.BackoffMultiplier) { $config.RetryPolicy.BackoffMultiplier } else { 2.0 }
    }

    # Default retryable patterns
    if (-not $RetryableErrorPatterns) {
        $RetryableErrorPatterns = @(
            'timeout',
            'timed out',
            'connection',
            'network',
            'socket',
            '429',
            'Too Many Requests',
            '503',
            'Service Unavailable',
            '504',
            'Gateway Timeout',
            'throttl',
            'temporarily unavailable',
            'transient',
            'ETIMEDOUT',
            'ECONNRESET',
            'ENOTFOUND'
        )
    }

    $attempt = 0
    $delay = $InitialDelayMs
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++

        try {
            Write-AutopilotLog -Level Debug -Message "$OperationName - Attempt $attempt/$MaxAttempts" -Phase 'Retry'
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message

            # Check if this is a retryable error
            $isRetryable = $false
            foreach ($pattern in $RetryableErrorPatterns) {
                if ($errorMessage -match $pattern) {
                    $isRetryable = $true
                    break
                }
            }

            # Don't retry if not a retryable error or we've exhausted attempts
            if (-not $isRetryable -or $attempt -ge $MaxAttempts) {
                Write-AutopilotLog -Level Error -Message "$OperationName failed after $attempt attempt(s)" -Phase 'Retry' -Data @{
                    ErrorMessage = $errorMessage
                    ErrorType    = $_.Exception.GetType().FullName
                    Retryable    = $isRetryable
                }
                throw
            }

            # Log and wait before retry
            Write-AutopilotLog -Level Warning -Message "$OperationName failed (attempt $attempt/$MaxAttempts). Retrying in $delay ms..." -Phase 'Retry' -Data @{
                ErrorMessage = $errorMessage
                DelayMs      = $delay
            }

            Start-Sleep -Milliseconds $delay

            # Calculate next delay with exponential backoff
            $delay = [int]($delay * $BackoffMultiplier)
        }
    }

    # Should not reach here, but just in case
    if ($lastError) {
        throw $lastError
    }
}
