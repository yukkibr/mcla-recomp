# Reversible toggle for the opt-in ReXGlue D3D12 scissor decoder cache.
# Usage: .\scripts\scissor_cache_trial.ps1 -Mode on|off|status
param([ValidateSet("on", "off", "status")][string]$Mode = "status")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root "out\build\win-amd64-release\mcla.toml"
$backupDir = Join-Path $root "out\phase2-backup\pre-scissor-cache"
$backup = Join-Path $backupDir "mcla.toml"
if (-not (Test-Path -LiteralPath $config)) { throw "Missing $config" }
if ($Mode -ne "status" -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw "Close the game before changing a startup-only D3D12 setting."
}
$raw = [IO.File]::ReadAllText($config)
$entry = [regex]::Match($raw, '(?m)^[ \t]*d3d12_scissor_cache[ \t]*=[ \t]*(true|false)')
if ($Mode -eq "status") {
    if ($entry.Success) {
        Write-Output ("d3d12_scissor_cache = " + $entry.Groups[1].Value)
    } else {
        Write-Output "d3d12_scissor_cache = false (SDK default)"
    }
    Write-Output ("Config: " + $config)
    exit 0
}
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
# Keep every other CVar untouched, including the successful
# 768/1024MB texture cache, Native 720p, FSR, parked cars, frame guard.
$raw = [regex]::Replace(
    $raw,
    '(?m)^[ \t]*d3d12_scissor_cache[ \t]*=[^\r\n]*(?:\r?\n|$)',
    '')
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
$enable = if ($Mode -eq "on") { "true" } else { "false" }
$raw += "`r`nd3d12_scissor_cache = $enable`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object Text.UTF8Encoding($false)))
Write-Output "DX12 scissor-cache trial: $Mode ($enable)"
Write-Output "Unmodified-game-config backup: $backup"
Write-Output "Restart the game to apply. For rollback, use -Mode off."
