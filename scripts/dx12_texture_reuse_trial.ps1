# Reversible opt-in DX12 GPU texture resource reuse; requires game restart.
# Usage: .\scripts\dx12_texture_reuse_trial.ps1 -Mode off|64|128|status
param([ValidateSet('off','64','128','status')][string]$Mode = 'status')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backup = Join-Path $root 'out\phase2-backup\pre-dx12-completed-resource-reuse\mcla.toml'
$key = 'd3d12_texture_resource_pool_mb'
if (-not (Test-Path -LiteralPath $config)) { throw "Missing config: $config" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing the DX12 resource reuse pool.'
}
$lines = @([IO.File]::ReadAllLines($config))
if ($Mode -eq 'status') {
    $current = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -eq $key })
    if ($current.Count -gt 0) { $current[-1] } else { "$key = 0 (default, OFF)" }
    $fps = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -eq 'mcla_fps' })
    if ($fps.Count -gt 0) { $fps[-1] }
    Write-Output "Config: $config"
    return
}
New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$value = if ($Mode -eq 'off') { '0' } else { $Mode }
$rows = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -ne $key })
$rows += "$key = $value"
[IO.File]::WriteAllLines($config, [string[]]$rows,
                          (New-Object Text.UTF8Encoding($false)))
Write-Output "DX12 resource pool: $value MB; restart game for changes."
Write-Output 'Only DX12 texture resource reuse size modified. FPS remains uncapped.'
Write-Output 'Verify city texture correctness; use -Mode off to disable after test.'
