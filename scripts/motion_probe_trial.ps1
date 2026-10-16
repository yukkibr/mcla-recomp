# Toggle optional read-only camera/target motion diagnostics.
# Usage: .\scripts\motion_probe_trial.ps1 -Mode on|off|status
param([ValidateSet("on", "off", "status")][string]$Mode = "status")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root "out\build\win-amd64-release\mcla.toml"
$backupDir = Join-Path $root "out\phase2-backup\pre-camera-target-probe"
$backup = Join-Path $backupDir "mcla.toml"
if (-not (Test-Path -LiteralPath $config)) { throw "No game mcla.toml: $config" }
if ($Mode -ne "status" -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw "Close the game before changing diagnostic settings."
}
$raw = [IO.File]::ReadAllText($config)
$match = [regex]::Match($raw, '(?m)^[ \t]*mcla_motion_probe[ \t]*=[ \t]*(true|false)')
if ($Mode -eq "status") {
    if ($match.Success) {
        Write-Output ("mcla_motion_probe = " + $match.Groups[1].Value)
    } else {
        Write-Output "mcla_motion_probe = false (default)"
    }
    Write-Output ("Config: " + $config)
    exit 0
}
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$raw = [regex]::Replace(
    $raw, '(?m)^[ \t]*mcla_motion_probe[ \t]*=[^\r\n]*(?:\r?\n|$)', '')
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
$enabled = if ($Mode -eq "on") { "true" } else { "false" }
$raw += "`r`nmcla_motion_probe = $enabled`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object Text.UTF8Encoding($false)))
Write-Output "MCLA camera/target motion probe: $Mode ($enabled)"
Write-Output "Only this diagnostic value changed. Restart game to apply."
