# Toggle read-only camera matrix identity trace for a controlled drive.
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='mcla_camera_publish_trace'
if(-not (Test-Path -LiteralPath $config)){throw "Missing configuration: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
  throw 'Close MCLA before changing the camera diagnostic setting.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
  $current=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
  if($current.Count){$current[-1]}else{"$key = false (default)"}
  Write-Output 'This option is read-only; no camera transform or physics is modified.'
  return
}
$backup=Join-Path $root 'out\phase2-backup\pre-camera-publish-identity-trace\mcla.toml'
if(-not (Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $config -Destination $backup
}
$val=if($Mode -eq 'on'){'true'}else{'false'}
$filtered=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$filtered += "$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$filtered,(New-Object Text.UTF8Encoding($false)))
Write-Output "MCLA camera publish identity diagnostic: $Mode"
Write-Output 'Only this diagnostic option changed. Reopen game before testing.'
