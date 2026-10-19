# Summarize ReXGlue texture hash-map creation and insertion timings.
param([ValidateRange(1,12)][int]$Recent=3,[string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$logdir=Join-Path $root 'out\build\win-amd64-release\logs'
$files=if($LogPaths.Count){@($LogPaths|ForEach-Object {Get-Item -LiteralPath $_})}
else{@(Get-ChildItem $logdir -File -Filter 'mcla_*.log'|
        Sort-Object LastWriteTime -Descending|Select-Object -First $Recent)}
$fields=@('creates','create_cpu_ms','create_peak_ms','insert_cpu_ms','insert_peak_ms',
          'rehashes','slow_create','slow_insert','live','buckets')
$rows=@()
foreach($file in $files){
  $raw=[IO.File]::ReadAllText($file.FullName)
  $reserve=@([regex]::Matches($raw,'Texture cache map reserve: entries=(\d+) buckets=(\d+)'))
  $reports=@([regex]::Matches($raw,'Texture cache map stats: ([^\r\n]+)'))
  $events=@([regex]::Matches($raw,'Texture cache map event: ([^\r\n]+)'))
  if(!$reports.Count){
    $rows += [pscustomobject]@{Log=$file.Name;Reserve=if($reserve.Count){$reserve[-1].Groups[1].Value}else{'unknown'};
      Windows=0;Creates='--';CreateMaxMs='--';InsertMaxMs='--';Rehashes='--';
      SlowCreate='--';SlowInsert='--';Live='--';Events=$events.Count}
    continue
  }
  $total=@{};$maxCreate=0.0;$maxInsert=0.0;$last=@{}
  foreach($r in $reports){
    $row=@{}
    foreach($pair in [regex]::Matches($r.Groups[1].Value,'([a-z_]+)=([0-9.]+)')){
      $row[$pair.Groups[1].Value]=$pair.Groups[2].Value
    }
    foreach($field in $fields){if(!$row.ContainsKey($field)){throw "$($file.Name): no $field"}}
    foreach($field in @('creates','rehashes','slow_create','slow_insert')){
      if(!$total.ContainsKey($field)){$total[$field]=0}
      $total[$field]+=[long]::Parse($row[$field])
    }
    $maxCreate=[math]::Max($maxCreate,[double]::Parse($row.create_peak_ms,[Globalization.CultureInfo]::InvariantCulture))
    $maxInsert=[math]::Max($maxInsert,[double]::Parse($row.insert_peak_ms,[Globalization.CultureInfo]::InvariantCulture))
    $last=$row
  }
  $rows += [pscustomobject]@{Log=$file.Name;Reserve=if($reserve.Count){$reserve[-1].Groups[1].Value}else{'OFF/unknown'};
      Windows=$reports.Count;Creates=$total.creates;CreateMaxMs=$maxCreate;InsertMaxMs=$maxInsert;
      Rehashes=$total.rehashes;SlowCreate=$total.slow_create;SlowInsert=$total.slow_insert;
      Live=$last.live;Events=$events.Count}
}
$rows|Format-Table -AutoSize|Out-String -Width 185|Write-Output
Write-Output 'Counters sum completed ~10s reporting windows and may omit the last partial interval.'
Write-Output 'Create/insert ms are CPU wall times, NOT GPU execution. A rehash means hash table grew, not a texture invalidation.'
Write-Output 'No samples means OFF or no successful new texture creations after enabling, not proof of zero problems.'
