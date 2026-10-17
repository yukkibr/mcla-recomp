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
    $excluded = @($rows | Select-Object -First $SkipFirst)
    if ($excluded.Count) {
        Write-Output "Excluded warmup/transition windows in $($file.Name):"
        $excluded | ForEach-Object {
            $x = $_.Data
            [pscustomobject]@{
                At=$_.Time; Gap100=[long]$x.gap100; Clamps=[long]$x.clamps
                Camera=[long]$x.camera_jumps; Relative15=[long]$x.relative_above_15m
                MaxGapMs=[math]::Round($x.max_gap_ms,1)
            }
        } | Format-Table -AutoSize | Out-String -Width 155 | Write-Output
    }
    $rows = @($rows | Select-Object -Skip $SkipFirst)
    if (!$rows.Count) { continue }
    $sum = @{}
    $max = 0.0
    $maxRelativeMm = 0.0
    $weightedRelativeMm = 0.0
    $maxTimerClipMs = 0.0
    $maxFixedClipMs = 0.0
    foreach ($row in $rows) {
        if ($row.Data.ContainsKey('relative_samples') -and $row.Data.ContainsKey('relative_avg_mm')) {
            $weightedRelativeMm += $row.Data.relative_samples * $row.Data.relative_avg_mm
        }
        if ($row.Data.ContainsKey('relative_max_mm')) {
            $maxRelativeMm = [math]::Max($maxRelativeMm, $row.Data.relative_max_mm)
        }
        foreach ($key in $row.Data.Keys) {
            if ($key -eq 'timer_max_clip_ms') {
                $maxTimerClipMs = [math]::Max($maxTimerClipMs, $row.Data[$key])
            } elseif ($key -eq 'fixed_max_clip_ms') {
                $maxFixedClipMs = [math]::Max($maxFixedClipMs, $row.Data[$key])
            } elseif ($key -eq 'max_gap_ms') {
                $max = [math]::Max($max, $row.Data[$key])
            } else {
                if (-not $sum.ContainsKey($key)) { $sum[$key] = 0.0 }
                $sum[$key] += $row.Data[$key]
            }
        }
    }
    $name = $file.Name
    $hasStepTelemetry = $sum.ContainsKey('timer_clipped_ms') -and $sum.ContainsKey('fixed_clipped_ms')
    $timerClip = if ($hasStepTelemetry) { [math]::Round($sum.timer_clipped_ms, 2) } else { '--' }
    $fixedClip = if ($hasStepTelemetry) { [math]::Round($sum.fixed_clipped_ms, 2) } else { '--' }
    $fixedCount = if ($hasStepTelemetry) { [long]$sum.fixed_calls } else { '--' }
    $fixedClamps = if ($hasStepTelemetry) { [long]$sum.fixed_clamps } else { '--' }
    $timerPeak = if ($hasStepTelemetry) { [math]::Round($maxTimerClipMs,2) } else { '--' }
    $hasBurst = $sum.ContainsKey('host_over90') -and $sum.ContainsKey('camera_cross60')
    $burst = @{}
    foreach ($field in @('host_over60','host_over90','fast_after_stall','camera_rate_reads','camera_over60','camera_cross60','camera_cross_near_stall')) {
        $burst[$field] = if ($hasBurst) { [long]$sum[$field] } else { '--' }
    }
    $peakCamera = if ($hasBurst) { [math]::Round(($rows | ForEach-Object { $_.Data.camera_peak_fps } | Measure-Object -Maximum).Maximum,1) } else { '--' }
    $fixedPeak = if ($hasStepTelemetry) { [math]::Round($maxFixedClipMs,2) } else { '--' }
    $relativeMean = if ($sum.relative_samples) { [math]::Round($weightedRelativeMm / $sum.relative_samples,1) } else { 0 }
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
        RelativeSamples=[long]$sum.relative_samples
        Relative05=[long]$sum.relative_above_05m
        Relative15=[long]$sum.relative_above_15m
        RelativeNear=[long]$sum.relative_near_gap
        RelativeMeanMm=$relativeMean
        RelativeMaxMm=[math]::Round($maxRelativeMm,0)
        TimerClipMs=$timerClip; TimerMaxClipMs=$timerPeak
        FixedCalls=$fixedCount; FixedClamps=$fixedClamps
        FixedClipMs=$fixedClip; FixedMaxClipMs=$fixedPeak
        Host60=$burst.host_over60; Host90=$burst.host_over90
        PostStallFast=$burst.fast_after_stall; CameraReads=$burst.camera_rate_reads
        CameraHigh=$burst.camera_over60; CameraCross60=$burst.camera_cross60
        CameraCrossNear=$burst.camera_cross_near_stall
        CameraPeakFps=$peakCamera
    }
    Write-Output "Per-window timing timeline: $name (first $SkipFirst windows skipped)"
    $rows | ForEach-Object {
        $x = $_.Data
        $t = if ($x.ContainsKey('timer_clipped_ms')) { [math]::Round($x.timer_clipped_ms,1) } else { '--' }
        $f = if ($x.ContainsKey('fixed_clipped_ms')) { [math]::Round($x.fixed_clipped_ms,1) } else { '--' }
        [pscustomobject]@{
            At=$_.Time; Gap50=[long]$x.gap50; Gap100=[long]$x.gap100
            Clamps=[long]$x.clamps; TimerClipMs=$t; FixedClipMs=$f
        }
    } | Format-Table -AutoSize | Out-String -Width 130 | Write-Output
    Write-Output "Per-window camera movement: $name"
    $rows | ForEach-Object {
        $x = $_.Data
        [pscustomobject]@{
            At=$_.Time; Camera=[long]$x.camera_jumps
            Target=[long]$x.target_jumps; Publish=[long]$x.publish_jumps
            Offset05=[long]$x.relative_above_05m; Offset15=[long]$x.relative_above_15m
        }
    } | Format-Table -AutoSize | Out-String -Width 130 | Write-Output
    if ($hasBurst) {
        Write-Output "Per-window high-FPS / camera 60-band events: $name"
        $rows | ForEach-Object {
            $x = $_.Data
            [pscustomobject]@{
                At=$_.Time; Host60=[long]$x.host_over60
                Host90=[long]$x.host_over90; AfterStall=[long]$x.fast_after_stall
                CamCross=[long]$x.camera_cross60; CrossNear=[long]$x.camera_cross_near_stall
                CamPeak=[math]::Round($x.camera_peak_fps,1)
            }
        } | Format-Table -AutoSize | Out-String -Width 150 | Write-Output
    }
}
if (!$totals.Count) {
    Write-Output 'No completed correlation windows. Enable the correlation trial and play for at least 20 seconds.'
    exit 0
}
Write-Output 'Read-only temporal association, NOT causal proof. Above22ms is an instantaneous interval proxy for below 45 FPS.'
Write-Output 'Near means a camera event within 250ms AFTER a measured present gap >=50ms.'
Write-Output 'Camera jumps compare same rig/owner, <120ms between reads, >6m displacement; NPC transforms are NOT sampled.'
Write-Output 'Relative offset is the vector difference between monitored camera rig and published camera; its change between successive comparable frames helps distinguish fixed offsets from motion.'
Write-Output 'Relative05/15 count offset changes >0.5m / >1.5m (heuristic, not necessarily flick). No NPC transforms are sampled.'
Write-Output 'Host60/90 count sub-16.667ms / sub-11.111ms guest presents, not an FPS average. CameraCross60 counts guest camera FPS-band switches during smoothing reads, not frames.'
Write-Output 'PostStallFast counts a <16.667ms present immediately following a >=50ms present. A correlation is not evidence of cause.'
Write-Output 'Presents and guest timer calls are different hooks; counters do not measure hardware GPU latency.'
Write-Output 'Frame/guest summaries:'
$totals | Select-Object Log,Windows,Presents,Over22Ms,Gap50,Gap100,MaxGapMs,Guest40,Guest67,Clamps |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output
Write-Output 'Camera/publish correlation summaries:'
$totals | Select-Object Log,CameraSamples,LongCameraGap,CameraJumps,TargetJumps,CameraNear,TargetNear,PublishJumps,PublishNear,RigDeviations |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Output
Write-Output 'Relative camera-to-render offset changes:'
$totals | Select-Object Log,RelativeSamples,Relative05,Relative15,RelativeNear,RelativeMeanMm,RelativeMaxMm |
    Format-Table -AutoSize | Out-String -Width 160 | Write-Output
Write-Output 'Measured duration withheld by each time-step guard (NOT additive across both hooks):'
$totals | Select-Object Log,TimerClipMs,TimerMaxClipMs,FixedCalls,FixedClamps,FixedClipMs,FixedMaxClipMs |
    Format-Table -AutoSize | Out-String -Width 170 | Write-Output
Write-Output 'The r8 and f11 paths may describe overlapping time. Never add their clipping totals to claim total lost gameplay time.'
Write-Output 'Transient FPS and camera 60-FPS threshold comparisons:'
$totals | Select-Object Log,Windows,Host60,Host90,PostStallFast,CameraReads,CameraHigh,CameraCross60,CameraCrossNear,CameraPeakFps |
    Format-Table -AutoSize | Out-String -Width 190 | Write-Output
