# Analyze optional guest timer/fixed-step vs guest present command callbacks.
param([ValidateRange(1,12)][int]$Recent=3,[string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$logFolder=Join-Path $root 'out\build\win-amd64-release\logs'
$logs=if($LogPaths.Count){@($LogPaths|ForEach-Object {Get-Item -LiteralPath $_})}
else{@(Get-ChildItem -LiteralPath $logFolder -Filter 'mcla_*.log' -File|
        Sort-Object LastWriteTime -Descending|Select-Object -First $Recent)}
$rows=@()
foreach($file in $logs){
    $raw=[IO.File]::ReadAllText($file.FullName)
    $windows=@([regex]::Matches($raw,'MCLA sim/present sync: ([^\r\n]+)'))
    $events=@([regex]::Matches($raw,'MCLA sim/present sync lag: ([^\r\n]+)'))
    $vals=@{}
    foreach($w in $windows){
        $f=@{}
        foreach($kv in [regex]::Matches($w.Groups[1].Value,'([a-z0-9_]+)=([0-9.]+)')){
            $f[$kv.Groups[1].Value]=$kv.Groups[2].Value
        }
        foreach($n in @('presents','no_new_fixed','multi_fixed','no_new_timer','age50',
                        'age100','timer_clamps','unpaired')){
            if(!$f.ContainsKey($n)){throw "$($file.Name): malformed $n"}
            if(!$vals.ContainsKey($n)){$vals[$n]=0}
            $vals[$n]+=[long]$f[$n]
        }
        if(!$vals.ContainsKey('max_age')){$vals.max_age=0}
        if(!$vals.ContainsKey('clipped')){$vals.clipped=0.0}
        $vals.max_age=[math]::Max($vals.max_age,[double]::Parse($f.age_peak_ms,[Globalization.CultureInfo]::InvariantCulture))
        $vals.clipped += [double]::Parse($f.timer_clipped_ms,[Globalization.CultureInfo]::InvariantCulture)
    }
    if(!$windows.Count){
        $rows += [pscustomobject]@{Log=$file.Name;Windows=0;Presents='--';NoStep='--';
            MultiStep='--';NoTimer='--';Age50='--';Age100='--';MaxAgeMs='--';
            Clamps='--';ClipMs='--';LagEvents=$events.Count}
        continue
    }
    $rows += [pscustomobject]@{Log=$file.Name;Windows=$windows.Count;
        Presents=$vals.presents;NoStep=$vals.no_new_fixed;
        MultiStep=$vals.multi_fixed;NoTimer=$vals.no_new_timer;
        Age50=$vals.age50;Age100=$vals.age100;MaxAgeMs=$vals.max_age;
        Clamps=$vals.timer_clamps;ClipMs=[math]::Round($vals.clipped,2);
        LagEvents=$events.Count}
    Write-Output "--- $($file.Name): raw lag events ---"
    $events | Select-Object -Last 15|ForEach-Object {$_.Value}
}
$rows|Format-Table -AutoSize|Out-String -Width 190|Write-Output
Write-Output 'A missing step means no fixed-step *hook* ran between two present calls; title screens may legitimately behave that way.'
Write-Output 'Fixed-step hook and present command are NOT physics vehicle transforms or displayed-screen timestamps.'
Write-Output 'Large fixed-step age cannot alone prove an invisible NPC collision; user reproduction time is needed.'
