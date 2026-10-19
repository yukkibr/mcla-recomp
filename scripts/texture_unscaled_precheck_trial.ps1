# Opt-in exact-key fast cache-hit lookup when internal draw scaling is OFF.
# Usage: .\scripts\texture_unscaled_precheck_trial.ps1 -Mode on|off|status
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='texture_precheck_unscaled_cache'
if(-not (Test-Path -LiteralPath $config)){throw "Missing config: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close MCLA before changing texture precheck.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
    $found=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($found.Count){$found[-1]}else{"$key = false (default)"}
    $fps=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq 'mcla_fps'})
    if($fps.Count){$fps[-1]}
    Write-Output 'Only an exact texture-cache lookup changes, and only with unscaled draws.'
    return
}
$backup=Join-Path $root 'out\phase2-backup\pre-texture-unscaled-precheck\mcla.toml'
if(-not (Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $config -Destination $backup
}
$val=if($Mode -eq 'on'){'true'}else{'false'}
$filtered=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$filtered += "$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$filtered,
                         (New-Object Text.UTF8Encoding($false)))
Write-Output "Unscaled texture-cache precheck: $Mode (requires game restart)"
Write-Output 'No FPS cap, physics, renderer, cache eviction, memory-watch, shader or FSR changes.'
