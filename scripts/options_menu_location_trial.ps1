# Experimental menu path selector: native retail OPTIONS versus original
# (working) pause SETTINGS fallback. Run with MCLA closed.
param([ValidateSet('options','settings','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='mcla_options_native_submenus'
if(!(Test-Path $config)){throw 'mcla.toml not found'}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
 $val=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
 if($val.Count){$val[-1]}else{"$key = true (default)"}
 return
}
if(Get-Process mcla -ErrorAction SilentlyContinue){throw 'Close game before changing menu location'}
$backup=Join-Path $root 'out\phase2-backup\pre-native-options-move\mcla.toml'
if(!(Test-Path $backup)){Copy-Item $config $backup}
$lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$val=if($Mode -eq 'options'){'true'}else{'false'}
$lines+="$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "DISPLAY/PERFORMANCE parent: $Mode (restart required)"
