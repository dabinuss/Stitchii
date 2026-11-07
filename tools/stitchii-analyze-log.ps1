# Analyze game frame pacing and pipeline errors without outputting usernames or file paths.
# Usage: .\tools\stitchii-analyze-log.ps1 -LogPath .\eden_log.txt
#        .\tools\stitchii-analyze-log.ps1 -LogPath .\stitchii.txt -CompareTo .\fritchii.txt
# Optional: -CsvPath .\numbers-only.csv
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $LogPath,
    [string] $CompareTo,
    [string] $CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LogStats {
    param([Parameter(Mandatory = $true)][string] $Path)

    $file = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $boots = 0
    $windows = 0
    [double]$frameSumUs = 0
    [long]$worstFrameUs = 0
    [long]$slowFrames = 0
    [long]$pipelineBuilds = 0
    [double]$pipelineGpuMs = 0
    [long]$textureErrors = 0
    [long]$ticIndexErrors = 0
    [long]$unmappedReads = 0
    [long]$drawsSkipped = 0
    [long]$fastmemFailures = 0
    $lastTextureExpected = $null
    $lastTextureCritical = $null
    $lastTexturePolicy = 'unknown'
    $frameGenStates = @{}
    $ootFpsStates = @{}

    foreach ($line in [System.IO.File]::ReadLines($file)) {
        if ($line.Contains('BootGame: Booting game:')) { $boots++ }
        if ($line -match 'last 600 presents: frame (\d+) us \(max (\d+), (\d+) over 100 ms\)') {
            $windows++
            $frameSumUs += [double]::Parse($Matches[1], $invariant)
            $worstFrameUs = [Math]::Max($worstFrameUs, [long]::Parse($Matches[2], $invariant))
            $slowFrames += [long]::Parse($Matches[3], $invariant)
        }
        if ($line -match 'Runtime pipelines in the last 10 s: (\d+) built, ([0-9.]+) ms on the GPU thread') {
            $pipelineBuilds += [long]::Parse($Matches[1], $invariant)
            $pipelineGpuMs += [double]::Parse($Matches[2], $invariant)
        }
        if ($line.Contains('Uncached read texture pixel format') -or
            $line.Contains('Uncached texture pixel format') -or
            $line.Contains('Uncached read texture type') -or
            $line.Contains('Uncached texture type')) {
            $textureErrors++
        }
        if ($line.Contains('assert index <= tic_limit') -or $line.Contains('Invalid shader TIC index:')) {
            $ticIndexErrors++
        }
        if ($line.Contains('Unmapped Device ReadBlock')) { $unmappedReads++ }
        if ($line.Contains('Draw skipped (no pipeline)')) { $drawsSkipped++ }
        if ($line -match 'Failed to allocate \d+ MiB of backing memory') { $fastmemFailures++ }
        if ($line -match 'Texture cache thresholds: expected (\d+) MiB, critical (\d+) MiB') {
            $lastTextureExpected = [int]$Matches[1]
            $lastTextureCritical = [int]$Matches[2]
        }
        if ($line -match 'Stitchii texture cache: policy=([a-zA-Z0-9-]+)') {
            $lastTexturePolicy = $Matches[1]
        }
        if ($line -match 'Renderer\.frame_gen: (true|false)') {
            $frameGenStates[$Matches[1]] = $true
        }
        if ($line -match 'Renderer\.oot_30fps: (true|false)') {
            $ootFpsStates[$Matches[1]] = $true
        }
    }

    $frameMs = if ($windows -gt 0) { [Math]::Round($frameSumUs / $windows / 1000, 2) } else { $null }
    $worstMs = if ($windows -gt 0) { [Math]::Round($worstFrameUs / 1000, 2) } else { $null }
    $fps = if ($windows -gt 0 -and $frameMs -gt 0) { [Math]::Round(1000 / $frameMs, 2) } else { $null }
    $frameGen = if ($frameGenStates.Count -eq 1) { @($frameGenStates.Keys)[0] } elseif ($frameGenStates.Count -gt 1) { 'mixed' } else { 'unknown' }
    $oot30 = if ($ootFpsStates.Count -eq 1) { @($ootFpsStates.Keys)[0] } elseif ($ootFpsStates.Count -gt 1) { 'mixed' } else { 'unknown' }

    # Deliberately output only aggregate counts and configuration booleans.
    # Never include file paths, usernames, game IDs, addresses, or driver fingerprints.
    [pscustomobject]@{
        Boots                 = $boots
        FrameWindows600       = $windows
        MeanPresentMs         = $frameMs
        EstimatedPresentFPS   = $fps
        WorstFrameMs          = $worstMs
        FramesOver100ms       = $slowFrames
        RuntimePipelines      = $pipelineBuilds
        PipelineGpuThreadMs   = [Math]::Round($pipelineGpuMs, 1)
        TextureReadFailures   = $textureErrors
        InvalidTicIndices     = $ticIndexErrors
        UnmappedDeviceReads   = $unmappedReads
        DrawsSkipped          = $drawsSkipped
        BackingMemoryFailures = $fastmemFailures
        TextureExpectedMiB    = $lastTextureExpected
        TextureCriticalMiB    = $lastTextureCritical
        TexturePolicy         = $lastTexturePolicy
        FrameGeneration       = $frameGen
        Oot30Fps              = $oot30
    }
}

function Show-Warnings {
    param($Stats)
    if ($Stats.Boots -ne 1) {
        Write-Warning "This log has $($Stats.Boots) game starts; use one game run per log for fair comparisons."
    }
    if ($Stats.FrameGeneration -eq 'mixed' -or $Stats.Oot30Fps -eq 'mixed') {
        Write-Warning 'Graphics settings changed within this log; the results are not a controlled benchmark.'
    }
    if ($Stats.FrameWindows600 -eq 0) {
        Write-Warning 'No 600-present windows were recorded; frame-time statistics are unavailable.'
    }
}

$latest = Get-LogStats -Path $LogPath
Write-Host 'STITCHII LOCAL PERFORMANCE SUMMARY (no personal data)' -ForegroundColor Cyan
$latest | Format-List
Show-Warnings -Stats $latest

if ($CompareTo) {
    $base = Get-LogStats -Path $CompareTo
    Write-Host 'REFERENCE LOG (aggregate metrics only)' -ForegroundColor Cyan
    $base | Format-List
    Show-Warnings -Stats $base

    $rows = foreach ($property in @('MeanPresentMs','WorstFrameMs','FramesOver100ms',
                                     'RuntimePipelines','PipelineGpuThreadMs','TextureReadFailures',
                                     'InvalidTicIndices','UnmappedDeviceReads','DrawsSkipped')) {
        $oldValue = $base.$property
        $newValue = $latest.$property
        $delta = if ($null -ne $oldValue -and [double]$oldValue -ne 0 -and $null -ne $newValue) {
            '{0:N1}%' -f (100 * ([double]$newValue - [double]$oldValue) / [double]$oldValue)
        } else { 'n/a' }
        [pscustomobject]@{
            Metric = $property
            Reference = $oldValue
            Stitchii = $newValue
            Delta = $delta
        }
    }
    Write-Host 'COMPARISON (negative deltas usually mean fewer stalls/errors)' -ForegroundColor Cyan
    $rows | Format-Table -AutoSize
    if ($base.FrameGeneration -ne $latest.FrameGeneration -or
        $base.Oot30Fps -ne $latest.Oot30Fps) {
        Write-Warning 'Different frame generation or OoT FPS settings: frame-time comparison may be misleading.'
    }
}

if ($CsvPath) {
    $latest | Export-Csv -LiteralPath $CsvPath -Encoding UTF8 -NoTypeInformation
    Write-Host 'Numeric-only CSV report created.' -ForegroundColor Green
}
