# Compare equal full 10-second gameplay windows of pool-on/off logs.
# Example: .\scripts\dx12_texture_reuse_report.ps1 -LogPaths @('...\mcla_043.log','...\mcla_044.log') -SkipFirst 4 -MaxWindows 6
param([int]$Recent=6,[int]$SkipFirst=3,[int]$MaxWindows=0,
      [string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$logDir=Join-Path $root 'out\build\win-amd64-release\logs'
$ci=[Globalization.CultureInfo]::InvariantCulture
$pattern='MCLA FPS benchmark: fps=(?<fps>[0-9.]+) avg_ms=(?<avg>[0-9.]+) p99_bucket_ms=(?<p99>[0-9]+) max_ms=(?<max>[0-9.]+) stalls50=(?<s50>[0-9]+) stalls100=(?<s100>[0-9]+) frames=(?<frames>[0-9]+) seconds=(?<secs>[0-9.]+)'
$files=if ($LogPaths.Count) {
    @($LogPaths | ForEach-Object { Get-Item -LiteralPath $_ })
} else {
    @(Get-ChildItem -LiteralPath $logDir -Filter 'mcla_*.log' -File |
      Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)
}
$rows=@()
foreach($file in $files) {
    $raw=[IO.File]::ReadAllText($file.FullName)
    $mode='OFF*'
    $active=[regex]::Match($raw,'DX12 texture resource reuse experiment: ([0-9]+) MB')
    if($active.Success){$mode= $active.Groups[1].Value+' MB'}
    $hits=@([regex]::Matches($raw,'DX12 texture resource pool: ([0-9]+) successful reuses'))
    [int64]$observed=0
    foreach($h in $hits){$observed=[math]::Max($observed,[long]$h.Groups[1].Value)}
    $windows=@([regex]::Matches($raw,$pattern) | Select-Object -Skip $SkipFirst)
    if($MaxWindows -gt 0){$windows=@($windows | Select-Object -First $MaxWindows)}
    if(!$windows.Count) { continue }
    [double]$secs=0;[long]$frames=0;[long]$stall50=0;[long]$stall100=0
    [double]$worst=0;[int]$p99=0
    foreach($w in $windows){
        $secs += [double]::Parse($w.Groups['secs'].Value,$ci)
        $frames += [long]$w.Groups['frames'].Value
        $stall50 += [long]$w.Groups['s50'].Value
        $stall100 += [long]$w.Groups['s100'].Value
        $worst=[math]::Max($worst,[double]::Parse($w.Groups['max'].Value,$ci))
        $p99=[math]::Max($p99,[int]$w.Groups['p99'].Value)
    }
    $rows += [pscustomobject]@{
        Log=$file.Name;Pool=$mode;Windows=$windows.Count
        Seconds=[math]::Round($secs,1);FPS=[math]::Round($frames/$secs,2)
        WorstMs=[math]::Round($worst,1);WorstP99Bucket=$p99
        Gaps50=$stall50;Gaps100=$stall100
        Gaps50Min=[math]::Round($stall50*60/$secs,2)
        ObservedReusesAtLeast=$observed
    }
}
Write-Output "First $SkipFirst completed windows excluded for initialization/transition."
Write-Output 'FPS = guest present requests/s, not hardware GPU rate.'
Write-Output 'ObservedReusesAtLeast is only the last power-of-two hit marker; zero is NOT proof that no resource was reused.'
Write-Output 'OFF* means no positive-pool activation marker was logged, not independent proof of configuration.'
Write-Output 'Compare the same roads/conditions and equal Numbers of Windows; visual inspection is mandatory.'
$rows | Format-Table -AutoSize | Out-String -Width 240 | Write-Output
