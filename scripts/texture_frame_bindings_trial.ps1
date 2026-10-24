# A/B for CPU texture processing at the START of each frame.
# OFF retains stock ReXGlue ResetTextureBindings() at every BeginFrame().
# ON preserves bindings when no texture load failed in the prior frame.
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='texture_preserve_clean_frame_bindings'
if(!(Test-Path -LiteralPath $config)){throw 'MCLA config not found'}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
 $values=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
 if($values.Count){$values[-1]}else{"$key = false (SDK default)"}
 return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close MCLA before changing texture binding mode'}
$backup=Join-Path $root 'out\phase2-backup\before-texture-frame-rebind-trial\mcla.toml'
New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null
if(!(Test-Path -LiteralPath $backup)){Copy-Item $config $backup}
$lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$value=if($Mode -eq 'on'){'true'}else{'false'}
$lines+="$key = $value"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Persistent clean texture bindings $Mode (requires restart)"
