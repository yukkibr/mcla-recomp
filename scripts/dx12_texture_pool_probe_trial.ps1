# Temporary DX12 pool resource-creation / lifetime telemetry. Keep pool size unchanged.
# .\scripts\dx12_texture_pool_probe_trial.ps1 -Mode on|off|status
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='d3d12_texture_resource_pool_probe'
if(-not (Test-Path -LiteralPath $config)){throw "Missing config: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close the game before changing DX12 resource pool telemetry.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
    $existing=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($existing.Count){$existing[-1]} else {"$key = false (default)"}
    $pool=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq 'd3d12_texture_resource_pool_mb'})
    if($pool.Count){$pool[-1]}
    $fps=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq 'mcla_fps'})
    if($fps.Count){$fps[-1]}
    return
}
$backup=Join-Path $root 'out\phase2-backup\pre-rexglue-texture-pool-telemetry\mcla.toml'
if(-not (Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $config -Destination $backup
}
$val=if($Mode -eq 'on'){'true'}else{'false'}
$filtered=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$filtered += "$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$filtered,(New-Object Text.UTF8Encoding($false)))
Write-Output "DX12 texture pool diagnostic $Mode. Requires a game restart."
Write-Output 'Texture pool size, FPS, FSR, Fast Path, sampler and game mechanics unchanged.'
