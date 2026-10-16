# Toggle read-only guest-frame timing telemetry in the existing release build.
# Usage: .\scripts\timing_trace_trial.ps1 -Mode on|off|status
param([ValidateSet("on", "off", "status")][string]$Mode = "status")
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root "out\build\win-amd64-release\mcla.toml"
$backupDir = Join-Path $root "out\phase2-backup\before-guest-timing-trace"
$backup = Join-Path $backupDir "mcla.toml"
if (-not (Test-Path -LiteralPath $config)) { throw "Game config missing: $config" }
if ($Mode -ne "status" -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw "Close MCLA before changing diagnostic settings."
}
$raw = [IO.File]::ReadAllText($config)
$found = [regex]::Match($raw, '(?m)^[ \t]*mcla_timing_trace[ \t]*=[ \t]*(true|false)')
if ($Mode -eq "status") {
    if ($found.Success) {
        Write-Output ("mcla_timing_trace = " + $found.Groups[1].Value)
    } else {
        Write-Output "mcla_timing_trace = false (default)"
    }
    Write-Output ("Config: " + $config)
    exit 0
}
New-Item -ItemType Directory -Force $backupDir | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$raw = [regex]::Replace(
    $raw,
    '(?m)^[ \t]*mcla_timing_trace[ \t]*=[^\r\n]*(?:\r?\n|$)',
    '')
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
$enabled = if ($Mode -eq "on") { "true" } else { "false" }
$raw += "`r`nmcla_timing_trace = $enabled`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object Text.UTF8Encoding($false)))
Write-Output "MCLA guest timing trace: $Mode ($enabled)"
Write-Output "Guest frame physics and camera code unchanged."
Write-Output "Restart the game to apply; disable for normal play after testing."
