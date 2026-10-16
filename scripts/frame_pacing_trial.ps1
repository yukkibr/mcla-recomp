# Reversible A/B test to distinguish uneven frame pacing from visual flick.
# Usage: .\scripts\frame_pacing_trial.ps1 -Mode 45|uncapped|status
param([ValidateSet("45", "uncapped", "status")][string]$Mode = "status")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root "out\build\win-amd64-release\mcla.toml"
$backupDir = Join-Path $root "out\phase2-backup\before-45fps-pacing-ab"
$backup = Join-Path $backupDir "mcla.toml"
if (-not (Test-Path -LiteralPath $config)) {
    throw "Missing MCLA config: $config"
}
if ($Mode -ne "status" -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw "Close the game before changing its FPS cap."
}
$raw = [IO.File]::ReadAllText($config)
$current = [regex]::Match($raw, '(?m)^[ \t]*mcla_fps[ \t]*=[ \t]*(-?\d+)')
if ($Mode -eq "status") {
    if ($current.Success) {
        Write-Output ("mcla_fps = " + $current.Groups[1].Value)
    } else {
        Write-Output "mcla_fps = 30 (SDK default)"
    }
    Write-Output ("Config: " + $config)
    exit 0
}
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$raw = [regex]::Replace($raw, '(?m)^[ \t]*mcla_fps[ \t]*=[^\r\n]*(?:\r?\n|$)', '')
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
$fps = if ($Mode -eq "45") { "45" } else { "0" }
$raw += "`r`nmcla_fps = $fps`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object Text.UTF8Encoding($false)))
Write-Output "MCLA FPS pacing experiment: $Mode (mcla_fps=$fps)"
Write-Output "Only FPS target was changed. All cache, FSR, 720p and frame-guard settings preserved."
Write-Output "Restart MCLA to apply. To revert, run with -Mode uncapped."
