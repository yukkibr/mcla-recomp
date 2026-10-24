# Texture-cache VRAM budget (NOT a hard limit for the entire game).
# The in-game DISPLAY menu persists mcla_texture_cache_budget_mb on exit.
param(
 [ValidateSet('legacy','auto','max','1024','1536','2048','3072','4096','5120','6144','status')]
 [string]$Mode='status',
 [ValidateSet('on','off','keep')][string]$CacheFlush='keep'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
if(!(Test-Path $config)){throw "Missing config: $config"}
if(($Mode -ne 'status' -or $CacheFlush -ne 'keep') -and (Get-Process mcla -ErrorAction SilentlyContinue)){
 throw 'Close MCLA before changing VRAM or flush settings.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
 foreach($key in @('mcla_texture_cache_budget_mb','texture_cache_memory_limit_soft',
  'texture_cache_memory_limit_hard','mcla_fast_guest_cache_flush','mcla_cache_flush_stats',
  'mcla_fps','mcla_gpu_backend')){
   $values=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
   if($values.Count){Write-Output $values[-1]}else{Write-Output "$key = (default)"}
 }
 return
}
$backup=Join-Path $root 'out\phase2-backup\pre-vram-menu\mcla.toml'
if(!(Test-Path $backup)){New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null;Copy-Item $config $backup}
$budget=@{legacy='-1';auto='0';max='-2'}
if($Mode -ne 'status'){
  $value=if($budget.ContainsKey($Mode)){$budget[$Mode]}else{$Mode}
  $lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne 'mcla_texture_cache_budget_mb'})
  $lines+="mcla_texture_cache_budget_mb = $value"
}
if($CacheFlush -ne 'keep'){
  $lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne 'mcla_fast_guest_cache_flush'})
  $v=if($CacheFlush -eq 'on'){'true'}else{'false'}
  $lines+="mcla_fast_guest_cache_flush = $v"
}
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Settings saved: VRAM cache=$Mode, CPU cache flush=$CacheFlush (restart game)."
Write-Output 'DXGI clamps requested texture cache to local adapter budget. This is NOT a full GPU VRAM cap.'
