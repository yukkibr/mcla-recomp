# Summarize ReXGlue's opt-in cumulative DX12 pool probe counters.
# Example: .\scripts\dx12_texture_pool_probe_report.ps1 -Recent 4
param([ValidateRange(1,40)][int]$Recent=4,[string[]]$LogPaths=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$logDir=Join-Path $root 'out\build\win-amd64-release\logs'
$files=if($LogPaths.Count) { @($LogPaths | ForEach-Object {Get-Item -LiteralPath $_}) }
       else { @(Get-ChildItem $logDir -Filter 'mcla_*.log' -File |
                 Sort-Object LastWriteTime -Descending | Select-Object -First $Recent) }
$rows=@()
$wanted=@('creations','create_failures','create_total_ms','create_peak_ms',
'recycle_attempts','recycled','reject_untracked','reject_busy','reject_oversized',
'reject_other','reuses','misses','desc_misses','evictions','pool_entries',
'pool_mb','pool_peak_mb')
foreach($file in $files){
  $raw=[IO.File]::ReadAllText($file.FullName)
  $enabled=[regex]::Match($raw,'DX12 texture pool probe active: pool_limit_mb=([0-9]+)')
  $reports=@([regex]::Matches($raw,'DX12 texture pool probe: (?<data>[^\r\n]+)'))
  if(-not $reports.Count){
    $rows += [pscustomobject]@{Log=$file.Name;Pool=if($enabled.Success){$enabled.Groups[1].Value+' MB'}else{'not measured'};Snapshots=0;Creates='--';CreateAvgMs='--';CreatePeakMs='--';Recycles='--';Stored='--';Busy='--';Untracked='--';TooLarge='--';Other='--';Reuses='--';DescMiss='--';PoolPeakMb='--'}
    continue
  }
  $data=@{}
  foreach($kv in ([regex]::Matches($reports[-1].Groups['data'].Value,'([a-z_]+)=([0-9.]+)'))){
    $data[$kv.Groups[1].Value]=$kv.Groups[2].Value
  }
  $missing=@($wanted | Where-Object {-not $data.ContainsKey($_)})
  if($missing.Count){throw "$($file.Name): missing probe fields $($missing -join ', ')"}
  $creates=[long]::Parse($data.creations)
  $total=[double]::Parse($data.create_total_ms,[Globalization.CultureInfo]::InvariantCulture)
  $avg=if($creates){[math]::Round($total/$creates,4)}else{0}
  $rows += [pscustomobject]@{
      Log=$file.Name
      Pool=if($enabled.Success){$enabled.Groups[1].Value+' MB'}else{'unknown'}
      Snapshots=$reports.Count
      Creates=$creates
      CreateAvgMs=$avg
      CreatePeakMs=$data.create_peak_ms
      Recycles=$data.recycle_attempts
      Stored=$data.recycled
      Busy=$data.reject_busy
      Untracked=$data.reject_untracked
      TooLarge=$data.reject_oversized
      Other=$data.reject_other
      Reuses=$data.reuses
      DescMiss=$data.desc_misses
      PoolPeakMb=$data.pool_peak_mb
  }
}
Write-Output 'DX12 pool lifetime counters (most recent completed 10-second snapshot; no GPU timestamps):'
$rows | Select-Object Log,Pool,Snapshots,Creates,CreateAvgMs,CreatePeakMs |
    Format-Table -AutoSize | Out-String -Width 135 | Write-Output
Write-Output 'Recycling and rejection totals:'
$rows | Select-Object Log,Recycles,Stored,Busy,Untracked,TooLarge,Other,Reuses,DescMiss,PoolPeakMb |
    Format-Table -AutoSize | Out-String -Width 180 | Write-Output
Write-Output 'Recycles = texture destruction callbacks, Stored = eligible resource stored; Reuses = exact matching checkout.'
Write-Output 'If Recycles stays zero but Creates increases, textures have not reached the destructor; changing pool size alone cannot help.'
Write-Output 'Busy = last GPU submission not completed, Untracked = missing submission number.'
Write-Output 'CreateAvgMs/PeakMs measure CPU wall time inside CreateCommittedResource, not GPU execution time.'
Write-Output 'No snapshots means NOT MEASURED, not a zero-counter result. Values can lag final shutdown activity.'
