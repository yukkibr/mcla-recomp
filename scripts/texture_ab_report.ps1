# Summarize opt-in guest-present FPS samples from original vs texture fast path.
# Example: .\scripts\texture_ab_report.ps1 -Recent 6 -SkipFirst 3
param([int]$Recent = 8, [int]$SkipFirst = 3, [string[]]$LogPaths = @())
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path $root 'out\build\win-amd64-release\logs'
$pattern = 'MCLA FPS benchmark: fps=(?<fps>[0-9.]+) avg_ms=(?<avg>[0-9.]+) p99_bucket_ms=(?<p99>[0-9]+) max_ms=(?<max>[0-9.]+) stalls50=(?<s50>[0-9]+) stalls100=(?<s100>[0-9]+) frames=(?<frames>[0-9]+) seconds=(?<secs>[0-9.]+)'
if ($LogPaths.Count) {
    $files = @($LogPaths | ForEach-Object { Get-Item -LiteralPath $_ })
} else {
    $files = @(Get-ChildItem -LiteralPath $logs -Filter 'mcla_*.log' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)
}
$rows = @()
foreach ($file in $files) {
    $raw = [IO.File]::ReadAllText($file.FullName)
    $mode = if ($raw.Contains('Texture fast path enabled:')) { 'ON' } else { 'OFF*' }
    $matches = @([regex]::Matches($raw, $pattern))
    $noOp = @([regex]::Matches($raw, 'Texture fast path: ([0-9]+) confirmed no-op'))
    $lastNoOp = if ($noOp.Count) { $noOp[$noOp.Count - 1].Groups[1].Value } else { '-' }
    $selected = @($matches | Select-Object -Skip $SkipFirst)
    if ($selected.Count -eq 0) {
        $rows += [pscustomobject]@{
            Log=$file.Name; Mode=$mode; Windows=0; FPS='--'; P99Bucket='--'
            WorstMs='--'; Stalls50='--'; Stalls100='--'; NoOp=$lastNoOp
        }
        continue
    }
    [double]$totalSeconds = 0
    [int64]$totalFrames = 0
    [int64]$stalls50 = 0
    [int64]$stalls100 = 0
    [double]$worst = 0
    [int]$highestP99Bucket = 0
    foreach ($m in $selected) {
        $totalSeconds += [double]::Parse($m.Groups['secs'].Value, $culture)
        $totalFrames += [int64]::Parse($m.Groups['frames'].Value, $culture)
        $stalls50 += [int64]::Parse($m.Groups['s50'].Value, $culture)
        $stalls100 += [int64]::Parse($m.Groups['s100'].Value, $culture)
        $worst = [math]::Max($worst, [double]::Parse($m.Groups['max'].Value, $culture))
        $highestP99Bucket = [math]::Max($highestP99Bucket, [int]$m.Groups['p99'].Value)
    }
    $rows += [pscustomobject]@{
        Log=$file.Name; Mode=$mode; Windows=$selected.Count
        FPS=[math]::Round($totalFrames/$totalSeconds, 2)
        P99Bucket=$highestP99Bucket; WorstMs=[math]::Round($worst, 1)
        Stalls50=$stalls50; Stalls100=$stalls100; NoOp=$lastNoOp
    }
}
Write-Output ('Frames: first {0} completed 10-second windows of each log excluded as warmup.' -f $SkipFirst)
Write-Output 'FPS = guest present requests per second (not necessarily physical display refresh).'
Write-Output 'P99Bucket = highest 1ms p99 bucket across included windows; 256 means >=256ms.'
Write-Output 'OFF* = no fast-path activation marker was seen; confirm trial settings if uncertain.'
$rows | Format-Table -AutoSize | Out-String -Width 240 | Write-Output
