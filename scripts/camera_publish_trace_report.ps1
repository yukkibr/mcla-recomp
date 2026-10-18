# Report read-only camera matrix identity source/rig transitions.
param([ValidateRange(1,12)][int]$Recent=3,[string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root 'out\build\win-amd64-release\logs'
$files=if($LogPaths.Count){@($LogPaths|ForEach-Object {Get-Item -LiteralPath $_})}
else {@(Get-ChildItem -LiteralPath $dir -Filter 'mcla_*.log' -File | Sort-Object LastWriteTime -Descending | Select-Object -First $Recent)}
foreach($file in $files){
    $data=[IO.File]::ReadAllLines($file.FullName)
    Write-Output "=== $($file.Name) ==="
    $summ=@()
    $events=@()
    $follows=@()
    foreach($line in $data){
        if($line -match 'MCLA camera identity trace active:') {
            if($line -match '^\[([^]]+)\]'){Write-Output ("$($Matches[1]) diagnostic enabled")}
            else {Write-Output 'Diagnostic enabled'}
        }
        if($line -match 'MCLA camera identity summary: '){
            $summ+=($line -replace '.*?(?=MCLA camera identity summary:)', '')
        } elseif($line -match 'MCLA camera identity event: '){
            $events+=($line -replace '^.*?\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+)\].*?MCLA camera identity event: ', '$1 ')
        } elseif($line -match 'MCLA camera identity follow: '){
            $follows+=($line -replace '^.*?\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+)\].*?MCLA camera identity follow: ', '$1 ')
        }
    }
    if(!$summ.Count -and !$events.Count){Write-Output 'No identity snapshots/events; the probe may be disabled or the driving camera hook was not active.';continue}
    Write-Output "10s summaries ($($summ.Count)):"
    $summ | Select-Object -Last 18 | ForEach-Object {Write-Output $_}
    Write-Output "Event-level matrix / rig details ($($events.Count)):"
    $events | Select-Object -Last 30 | ForEach-Object {Write-Output $_}
    Write-Output "Follow-up publication samples ($($follows.Count)):"
    $follows | Select-Object -Last 25 | ForEach-Object {Write-Output $_}
}
Write-Output 'SOURCE SWITCH only identifies a new matrix pointer; it does not itself prove a legitimate cutscene or a flick.'
Write-Output 'JUMP SAME MATRIX is more suspicious if the owner/rig is unchanged, but still needs visual timestamp confirmation.'
