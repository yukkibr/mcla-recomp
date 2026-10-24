# ReXGlue DX12 scissor-cache METRICS (not the caching itself).
# A/B keeps exact same cached rectangles and render commands.
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='d3d12_scissor_cache_stats'
if(!(Test-Path -LiteralPath $config)){throw "Missing config: $config"}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
  $entry=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
  if($entry.Count){$entry[-1]}else{"$key = false (SDK default)"}
  $other=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq 'd3d12_scissor_cache'})
  if($other.Count){$other[-1]}
  return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close MCLA before toggling startup-only stats.'}
$folder=Join-Path $root 'out\phase2-backup\pre-scissor-stats-off'
$backup=Join-Path $folder 'mcla.toml'
New-Item -ItemType Directory -Force $folder|Out-Null
if(!(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $config -Destination $backup}
$lines=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$val=if($Mode -eq 'on'){'true'}else{'false'}
$lines += "$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Scissor cache statistics: $Mode; caching remains unchanged. Restart MCLA."
