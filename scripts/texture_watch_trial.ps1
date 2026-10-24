# Reversible watch invalidation optimization for unscaled guest textures.
# Memory invalidation still triggers texture reload; do not use with visual
# bugs until the original FULL RESET mode is compared.
param([ValidateSet('on','off','status')][string]$Mode='status',
      [ValidateSet('keep','on','off')][string]$Stats='keep')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$keys=@('texture_watch_selective_invalidation','texture_watch_selective_stats')
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
 foreach($key in $keys){
   $entry=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
   if($entry.Count){Write-Output $entry[-1]}else{Write-Output "$key = false (SDK default)"}
 }
 return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close game before toggling selective watch invalidation'}
$backup=Join-Path $root 'out\phase2-backup\pre-texture-translation-wave-2\mcla.toml'
New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null
if(!(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $config -Destination $backup}
$changes=@{'texture_watch_selective_invalidation'=$(if($Mode -eq 'on'){'true'}else{'false'})}
if($Stats -ne 'keep'){$changes['texture_watch_selective_stats']=$(if($Stats -eq 'on'){'true'}else{'false'})}
$lines=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -notin @($changes.Keys)})
foreach($key in @($changes.Keys)){$lines+="$key = $($changes[$key])"}
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Texture watch selective invalidation $Mode (restart game); stats $Stats."
Write-Output "OFF restores ReXGlue full-reset behavior; graphics and guest physics are untouched."
