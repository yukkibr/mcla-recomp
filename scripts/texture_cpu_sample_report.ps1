# Analyze reversible, sparse CPU timing samples from TextureCache::RequestTextures.
# Use after the game was run with -Sampler on (short diagnostic runs only).
param([int]$Recent = 8, [string[]]$LogPaths = @())
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$logsDir = Join-Path $root 'out\build\win-amd64-release\logs'
$ci = [Globalization.CultureInfo]::InvariantCulture
if ($LogPaths.Count) {
    $logs = @($LogPaths | ForEach-Object { Get-Item -LiteralPath $_ })
} else {
    $logs = @(Get-ChildItem -LiteralPath $logsDir -Filter 'mcla_*.log' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)
}
$schema = 'Texture request sample: total=(?<total>\d+) skipped=(?<skipped>\d+) original_noop=(?<original_noop>\d+) active=(?<active>\d+) sampled_skip=(?<sampled_skip>\d+) sampled_noop=(?<sampled_noop>\d+) sampled_active=(?<sampled_active>\d+) avg_skip_us=(?<avg_skip_us>[\d.]+) avg_noop_us=(?<avg_noop_us>[\d.]+) avg_active_prep_us=(?<avg_active_prep_us>[\d.]+) avg_active_resident_us=(?<avg_active_resident_us>[\d.]+) avg_active_upload_us=(?<avg_active_upload_us>[\d.]+) avg_active_binding_us=(?<avg_active_binding_us>[\d.]+) slow_active_samples=(?<slow_active_samples>\d+) max_sampled_active_ms=(?<max_sampled_active_ms>[\d.]+)'
$results = @()
foreach ($file in $logs) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $mode = if ($text.Contains('Texture fast path enabled:')) { 'ON' } else { 'OFF*' }
    $matches = @([regex]::Matches($text, $schema))
    if (!$matches.Count) { continue }
    $sum = @{}
    $aggregates = @('total','skipped','original_noop','active','sampled_skip','sampled_noop','sampled_active','slow_active_samples')
    $weighted = @{
        avg_skip_us='sampled_skip'
        avg_noop_us='sampled_noop'
        avg_active_prep_us='sampled_active'
        avg_active_resident_us='sampled_active'
        avg_active_upload_us='sampled_active'
        avg_active_binding_us='sampled_active'
    }
    foreach ($k in $aggregates) { $sum[$k] = [double]0 }
    foreach ($k in $weighted.Keys) { $sum[$k] = [double]0 }
    $maxMs = [double]0
    foreach ($m in $matches) {
        foreach ($k in $aggregates) {
            $sum[$k] += [double]::Parse($m.Groups[$k].Value, $ci)
        }
        foreach ($k in $weighted.Keys) {
            $v = [double]::Parse($m.Groups[$k].Value, $ci)
            $n = [double]::Parse($m.Groups[$weighted[$k]].Value, $ci)
            $sum[$k] += $v * $n
        }
        $maxMs = [math]::Max($maxMs, [double]::Parse($m.Groups['max_sampled_active_ms'].Value, $ci))
    }
    $avg = @{}
    foreach ($k in $weighted.Keys) {
        $samples = $sum[$weighted[$k]]
        $avg[$k] = if ($samples) { [math]::Round($sum[$k] / $samples, 2) } else { $null }
    }
    $noopPercent = if ($sum.total) {
        [math]::Round(100 * ($sum.skipped + $sum.original_noop) / $sum.total, 1)
    } else { 0 }
    $results += [pscustomobject]@{
        Log=$file.Name; Mode=$mode; Windows=$matches.Count
        Requests=[long]$sum.total; NoopPct=$noopPercent
        Skipped=[long]$sum.skipped; OriginalNoop=[long]$sum.original_noop
        Active=[long]$sum.active; SkipUs=$avg.avg_skip_us
        OriginalNoopUs=$avg.avg_noop_us
        ActivePrepUs=$avg.avg_active_prep_us
        ActiveResidencyUs=$avg.avg_active_resident_us
        ActiveUploadUs=$avg.avg_active_upload_us
        ActiveBindingUs=$avg.avg_active_binding_us
        SampledSlowActive=[long]$sum.slow_active_samples; SampledMaxMs=$maxMs
    }
}
if (!$results.Count) {
    Write-Output 'No completed texture sampling windows. Run each mode with -Sampler on and drive at least 20 seconds.'
    exit 0
}
Write-Output 'Times are per-call sampled CPU microseconds (1 in 257 requests), not GPU timing.'
Write-Output 'NoopPct counts unchanged bindings (skipped in ON mode, processed in OFF mode).'
Write-Output 'SampledMaxMs is not the real peak; unsampled spikes may be missed.'
Write-Output 'OFF* means no ON marker; verify the mode from the run settings.'
Write-Output 'Request breakdown:'
$results | Select-Object Log,Mode,Windows,Requests,NoopPct,Skipped,OriginalNoop,Active |
    Format-Table -AutoSize | Out-String -Width 180 | Write-Output
Write-Output 'CPU cost per sampled request (microseconds):'
$results | Select-Object Log,Mode,SkipUs,OriginalNoopUs,ActivePrepUs,ActiveResidencyUs,ActiveUploadUs,ActiveBindingUs |
    Format-Table -AutoSize | Out-String -Width 180 | Write-Output
Write-Output 'Sparse sampled outliers (NOT all spikes):'
$results | Select-Object Log,Mode,SampledSlowActive,SampledMaxMs |
    Format-Table -AutoSize | Out-String -Width 100 | Write-Output
