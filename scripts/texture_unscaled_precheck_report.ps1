# Inspect ReXGlue's cumulative exact-cache-hit precheck counters in game logs.
param([ValidateRange(1,15)][int]$Recent=4,[string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$folder=Join-Path $root 'out\build\win-amd64-release\logs'
$files=if($LogPaths.Count) {@($LogPaths | ForEach-Object {Get-Item -LiteralPath $_})}
else {@(Get-ChildItem -LiteralPath $folder -Filter 'mcla_*.log' -File |
         Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)}
$rows=@()
foreach($f in $files){
    $matches=@([regex]::Matches([IO.File]::ReadAllText($f.FullName),
        'Texture unscaled precheck: (?<attempts>\d+) exact lookups, (?<hits>\d+) hits \((?<rate>[\d.]+)%\)'))
    if($matches.Count -eq 0){
        $rows += [pscustomobject]@{Log=$f.Name;Samples='none';Checks='--';Hits='--';Rate='--'}
        continue
    }
    $v=$matches[-1]
    [double]$tries=[double]::Parse($v.Groups['attempts'].Value)
    [double]$hits=[double]::Parse($v.Groups['hits'].Value)
    $rows += [pscustomobject]@{Log=$f.Name;Samples=$matches.Count;
        Checks=$v.Groups['attempts'].Value;Hits=$v.Groups['hits'].Value;
        Rate=([math]::Round(100.0*$hits/$tries,3).ToString()+'%')}
}
$rows | Format-Table -AutoSize | Out-String -Width 140 | Write-Output
Write-Output 'No checkpoint means disabled OR fewer than 5000 attempts; do not interpret as zero cache hits.'
Write-Output 'These are exact-key cache lookups, not count of saved texture allocations.'
Write-Output 'Compare route-matched runs via scripts/texture_ab_report.ps1; FPS changes are not implied by hit rate.'
