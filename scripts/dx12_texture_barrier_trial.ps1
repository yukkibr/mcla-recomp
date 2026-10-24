# Experimental CPU optimization: avoids redundant host
# PushTransitionBarrier calls when texture is already shader-readable.
# All real D3D12 resource state transitions remain identical.
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='d3d12_texture_read_barrier_elision'
if(!(Test-Path -LiteralPath $config)){throw 'Game config missing'}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
  $entry=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
  if($entry.Count){$entry[-1]}else{"$key = false (SDK default)"}
  return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close MCLA before updating startup-only optimization'}
$bak=Join-Path $root 'out\phase2-backup\pre-texture-read-barrier-elision\mcla.toml'
if(!(Test-Path -LiteralPath $bak)){Copy-Item -LiteralPath $config -Destination $bak}
$lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$v=if($Mode -eq 'on'){'true'}else{'false'}
$lines+="$key = $v"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "DX12 redundant texture read barrier call elision: $Mode; restart MCLA."
