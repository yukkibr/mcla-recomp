# Two independent DX12 texture translation CPU hotpaths:
# * texture_request_quick_sync: early return for already-synced textures;
# * d3d12_texture_3d_binding_mask: avoid checking 2D slots for 3D wrappers.
# Does NOT change texture conversion shaders, graphics API, VRAM, physics or settings.
param([ValidateSet('on','off','status')][string]$Mode='status',
      [ValidateSet('both','sync','3d')][string]$Part='both')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
if(!(Test-Path -LiteralPath $config)){throw "Missing config: $config"}
$keys=@('texture_request_quick_sync','d3d12_texture_3d_binding_mask')
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
  foreach($key in @($keys+@('texture_request_fast_path','d3d12_scissor_cache','d3d12_scissor_cache_stats'))){
    $v=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($v.Count){Write-Output $v[-1]}else{Write-Output "$key = (built-in default)"}
  }
  return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close MCLA before editing GPU cache startup flags'}
$backup=Join-Path $root 'out\phase2-backup\pre-texture-translation-wave-1\mcla.toml'
New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null
if(!(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $config -Destination $backup}
$apply=if($Part -eq 'both'){$keys}elseif($Part -eq 'sync'){@($keys[0])}else{@($keys[1])}
$value=if($Mode -eq 'on'){'true'}else{'false'}
$lines=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -notin $apply})
foreach($key in $apply){$lines+="$key = $value"}
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Texture CPU fastpaths set to $Mode for $Part. Restart MCLA."
Write-Output 'Texture invalidation, original conversion shaders and GPU uploads stay unchanged.'
