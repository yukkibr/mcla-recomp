# Controlled GPU-safe deferred texture memory recycling A/B. Does not
# alter physical VRAM capacity, current 128-MiB pool cap, or frame sync.
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='d3d12_texture_deferred_recycle'
if(!(Test-Path $config)){throw 'Missing configuration'}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
 foreach($k in @($key,'d3d12_texture_resource_pool_mb','d3d12_texture_resource_pool_probe')){
  $v=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $k})
  if($v.Count){Write-Output $v[-1]}else{Write-Output "$k = <SDK default>"}
 }
 return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close MCLA before changing DX12 pool'}
$backup=Join-Path $root 'out\phase2-backup\pre-deferred-gpu-texture-reuse\mcla.toml'
if(!(Test-Path $backup)){Copy-Item $config $backup -Force}
$lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$v=if($Mode -eq 'on'){'true'}else{'false'}
$lines+="$key = $v"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Deferred GPU-safe DX12 texture pooling $Mode, restart required."
