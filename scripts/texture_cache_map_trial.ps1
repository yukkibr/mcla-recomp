# Optional pre-allocation of ReXGlue texture cache's hash map; probe is read-only.
# Usage: .\scripts\texture_cache_map_trial.ps1 -Mode off|8192|16384|status [-Probe on|off|keep]
param(
 [ValidateSet('off','8192','16384','status')][string]$Mode='status',
 [ValidateSet('on','off','keep')][string]$Probe='keep'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
if(-not (Test-Path -LiteralPath $config)){throw "Config not found: $config"}
if(($Mode -ne 'status' -or $Probe -ne 'keep') -and
   (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close MCLA before changing map reserve/probe settings.'
}
$lines=@([IO.File]::ReadAllLines($config))
function Get-Value([string]$key,[string]$fallback){
  $values=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
  if($values.Count){$values[-1]}else{"$key = $fallback (default)"}
}
if($Mode -eq 'status'){
    Get-Value 'texture_cache_map_reserve' '0'
    Get-Value 'texture_cache_map_probe' 'false'
    Get-Value 'mcla_fps' '30'
    return
}
$backup=Join-Path $root 'out\phase2-backup\pre-texture-cache-map-reserve\mcla.toml'
if(-not (Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $config -Destination $backup
}
$key='texture_cache_map_reserve'
$lines=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$num=if($Mode -eq 'off'){'0'}else{$Mode}
$lines += "$key = $num"
if($Probe -ne 'keep'){
    $key='texture_cache_map_probe'
    $lines=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
    $val=if($Probe -eq 'on'){'true'}else{'false'}
    $lines += "$key = $val"
}
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Texture cache hash bucket reserve: $num entries; trace=$Probe (requires restart for reserve)"
Write-Output 'Texture retention/invalidation, FPS, camera, FSR, guest timings and GPU resource limits unchanged.'
