[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^http://127\.0\.0\.1:\d+$')]
    [string]$ApiUrl,

    [Parameter(Mandatory = $true)]
    [ValidateLength(16, 512)]
    [string]$Token,

    [ValidateSet('same-lan', 'public-ipv4-vps', 'port-forward', 'cgnat-hotspot')]
    [string]$Topology = 'same-lan',

    [ValidateRange(1, 86400)]
    [int]$Samples = 1800,

    [ValidateRange(1, 60)]
    [int]$IntervalSeconds = 1,

    [string]$OutputPath = (Join-Path (Get-Location) 'remote-session-metrics.jsonl')
)

$ErrorActionPreference = 'Stop'
$headers = @{ Authorization = "Bearer $Token" }
$health = Invoke-RestMethod -Method Get -Uri "$ApiUrl/v1/health" -Headers $headers
if (-not $health.ok) {
    throw 'LDesk debug API health check failed.'
}

$output = [IO.Path]::GetFullPath($OutputPath)
$summaryPath = [IO.Path]::ChangeExtension($output, '.summary.json')
$outputDirectory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$latest = @{}
for ($sample = 1; $sample -le $Samples; $sample++) {
    $capturedAt = [DateTimeOffset]::UtcNow
    try {
        $response = Invoke-RestMethod -Method Get -Uri "$ApiUrl/v1/sessions" -Headers $headers
        foreach ($session in @($response.sessions)) {
            $firstFrameMs = $null
            if ($null -ne $session.first_frame_at_ms) {
                $firstFrameMs = [int64]$session.first_frame_at_ms - [int64]$session.connected_at_ms
            }
            $record = [ordered]@{
                captured_at = $capturedAt.ToString('o')
                topology = $Topology
                sample = $sample
                peer_id = $session.peer_id
                attempt = $session.attempt
                handshake_successes = $session.handshake_successes
                first_frame_successes = $session.first_frame_successes
                direct_successes = $session.direct_successes
                relay_successes = $session.relay_successes
                error_attempts = $session.error_attempts
                disconnects = $session.disconnects
                stable_30m_completions = $session.stable_30m_completions
                first_frame_latency_total_ms = $session.first_frame_latency_total_ms
                state = $session.state
                secure = $session.secure
                route = if ($session.direct) { 'direct' } else { 'relay' }
                stream_type = $session.stream_type
                connected_at_ms = $session.connected_at_ms
                first_frame_at_ms = $session.first_frame_at_ms
                first_frame_latency_ms = $firstFrameMs
                disconnected_at_ms = $session.disconnected_at_ms
                last_session_duration_ms = $session.last_session_duration_ms
                last_error = $session.last_error
            }
            Add-Content -LiteralPath $output -Value ($record | ConvertTo-Json -Compress)
            $latest[$session.peer_id] = [pscustomobject]$record
        }
    } catch {
        $record = [ordered]@{
            captured_at = $capturedAt.ToString('o')
            topology = $Topology
            sample = $sample
            api_error = $_.Exception.Message
        }
        Add-Content -LiteralPath $output -Value ($record | ConvertTo-Json -Compress)
    }

    if ($sample -lt $Samples) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}

$sessions = @($latest.Values)
$attempts = [int](($sessions | Measure-Object -Property attempt -Sum).Sum)
$firstFrameSuccesses = [int](($sessions | Measure-Object -Property first_frame_successes -Sum).Sum)
$firstFrameLatencyTotal = [double](($sessions | Measure-Object -Property first_frame_latency_total_ms -Sum).Sum)
$handshakeSuccesses = [int](($sessions | Measure-Object -Property handshake_successes -Sum).Sum)
$directSuccesses = [int](($sessions | Measure-Object -Property direct_successes -Sum).Sum)
$summary = [ordered]@{
    topology = $Topology
    samples = $Samples
    interval_seconds = $IntervalSeconds
    peers = $sessions.Count
    attempts = $attempts
    handshake_successes = $handshakeSuccesses
    first_frame_successes = $firstFrameSuccesses
    direct_successes = $directSuccesses
    relay_successes = [int](($sessions | Measure-Object -Property relay_successes -Sum).Sum)
    error_attempts = [int](($sessions | Measure-Object -Property error_attempts -Sum).Sum)
    disconnects = [int](($sessions | Measure-Object -Property disconnects -Sum).Sum)
    stable_30m_completions = [int](($sessions | Measure-Object -Property stable_30m_completions -Sum).Sum)
    handshake_success_rate_percent = if ($attempts -gt 0) {
        [math]::Round(100 * $handshakeSuccesses / $attempts, 2)
    } else { $null }
    first_frame_success_rate_percent = if ($attempts -gt 0) {
        [math]::Round(100 * $firstFrameSuccesses / $attempts, 2)
    } else { $null }
    direct_rate_percent = if ($handshakeSuccesses -gt 0) {
        [math]::Round(100 * $directSuccesses / $handshakeSuccesses, 2)
    } else { $null }
    average_first_frame_latency_ms = if ($firstFrameSuccesses -gt 0) {
        [math]::Round($firstFrameLatencyTotal / $firstFrameSuccesses, 2)
    } else {
        $null
    }
    metrics_path = $output
}

$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath
$summary | ConvertTo-Json
