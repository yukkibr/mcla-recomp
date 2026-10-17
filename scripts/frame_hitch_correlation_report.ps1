# Summarize read-only guest/present/camera correlation from recent MCLA logs.
# Example: .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3
param([int]$Recent = 6, [int]$SkipFirst = 3, [string[]]$LogPaths = @())
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path $root 'out\build\win-amd64-release\logs'
$ci = [Globalization.CultureInfo]::InvariantCulture
if ($LogPaths.Count) {
    $files = @($LogPaths | ForEach-Object { Get-Item -LiteralPath $_ })
} else {
    $files = @(Get-ChildItem -LiteralPath $logs -Filter 'mcla_*.log' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)
}
$totals = @()
foreach ($file in $files) {
    $rows = @()
    $start = 'MCLA hitch correlate: present='
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
        if (-not $line.Contains($start)) { continue }
        $fields = @{}
        foreach ($match in [regex]::Matches($line, '([a-z][a-z0-9_]+)=([0-9]+(?:\.[0-9]+)?)')) {
            $fields[$match.Groups[1].Value] = [double]::Parse($match.Groups[2].Value, $ci)
        }
        if (-not $fields.ContainsKey('present') -or -not $fields.ContainsKey('gap50')) {
            continue
        }
        $when = if ($line -match '^\[(?<date>[^\]]+)\]') { $Matches.date } else { '?' }
        $rows += [pscustomobject]@{ Time=$when; Data=$fields }
    }
    $rows = @($rows | Select-Object -Skip $SkipFirst)
    if (!$rows.Count) { continue }
    $sum = @{}
    $max = 0.0
    foreach ($row in $rows) {
        foreach ($key in $row.Data.Keys) {
            if ($key -eq 'max_gap_ms') {
                $max = [math]::Max($max, $row.Data[$key])
            } else {
                if (-not $sum.ContainsKey($key)) { $sum[$key] = 0.0 }
                $sum[$key] += $row.Data[$key]
            }
        }
    }
    $name = $file.Name
    $totals += [pscustomobject]@{
        Log=$name; Windows=$rows.Count; Presents=[long]$sum.present
        Over22Ms=[long]$sum.intervals_above_22ms; Gap50=[long]$sum.gap50
        Gap100=[long]$sum.gap100; MaxGapMs=[math]::Round($max,1)
        Guest40=[long]$sum.guest40; Guest67=[long]$sum.guest67
        Clamps=[long]$sum.clamps; CameraSamples=[long]$sum.camera_updates
        LongCameraGap=[long]$sum.long_camera_gaps
        CameraJumps=[long]$sum.camera_jumps; TargetJumps=[long]$sum.target_jumps
        CameraNear=[long]$sum.camera_near_gap; TargetNear=[long]$sum.target_near_gap
        PublishJumps=[long]$sum.publish_jumps
        PublishNear=[long]$sum.publish_near_gap
        RigDeviations=[long]$sum.rig_deviations
    }
    Write-Output "Per-window hitch timeline: $name (first $SkipFirst windows skipped)"
    $rows | ForEach-Object {
        $x = $_.Data
        [pscustomobject]@{
            At=$_.Time; Gap50=[long]$x.gap50; Gap100=[long]$x.gap100
            Clamps=[long]$x.clamps; Camera=[long]$x.camera_jumps
            Target=[long]$x.target_jumps; Publish=[long]$x.publish_jumps
        }
    } | Format-Table -AutoSize | Out-String -Width 160 | Write-Output
}
if (!$totals.Count) {
    Write-Output 'No completed correlation windows. Enable the correlation trial and play for at least 20 seconds.'
    exit 0
}
Write-Output 'Read-only temporal association, NOT causal proof. Above22ms is an instantaneous interval proxy for below 45 FPS.'
Write-Output 'Near means a camera event within 250ms AFTER a measured present gap >=50ms.'
Write-Output 'Camera jumps compare same rig/owner, <120ms between reads, >6m displacement; NPC transforms are NOT sampled.'
Write-Output 'Presents and guest timer calls are different hooks; counters do not measure hardware GPU latency.'
Write-Output 'Frame/guest summaries:'
$totals | Select-Object Log,Windows,Presents,Over22Ms,Gap50,Gap100,MaxGapMs,Guest40,Guest67,Clamps |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output
Write-Output 'Camera/publish correlation summaries:'
$totals | Select-Object Log,CameraSamples,LongCameraGap,CameraJumps,TargetJumps,CameraNear,TargetNear,PublishJumps,PublishNear,RigDeviations |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output
