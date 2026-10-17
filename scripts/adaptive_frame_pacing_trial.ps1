# Reversible optional frame pacing: no change to mcla_fps itself.
# Usage: .\scripts\adaptive_frame_pacing_trial.ps1 -Mode off|adaptive|steady45|status
param([ValidateSet('off','adaptive','steady45','status')][string]$Mode='status')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cfg = Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backup = Join-Path $root 'out\phase2-backup\pre-adaptive-frame-pacing\mcla.toml'
if (-not (Test-Path -LiteralPath $cfg)) { throw "Config not found: $cfg" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing its experimental frame pacing mode.'
}
$lines = @([IO.File]::ReadAllLines($cfg))
$key = 'mcla_frame_pacing_mode'
if ($Mode -eq 'status') {
    $found = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -eq $key })
    if ($found.Count) { $found[-1] } else { "$key = off (default)" }
    $fps = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -eq 'mcla_fps' })
    if ($fps.Count) { Write-Output $fps[-1] }
    Write-Output 'An explicit positive mcla_fps target overrides this experimental mode.'
    Write-Output "Config: $cfg"
    return
}
New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $cfg -Destination $backup }
$filtered = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -ne $key })
$filtered += ($key + ' = ' + [char]34 + $Mode + [char]34)
[IO.File]::WriteAllLines($cfg, [string[]]$filtered,
                         (New-Object Text.UTF8Encoding($false)))
Write-Output "MCLA frame pacing mode: $Mode. Apply on next game launch."
Write-Output 'OFF: uncapped; ADAPTIVE: dynamic 45-90 FPS timer ceiling; STEADY45: fixed 45 FPS.'
Write-Output 'Only mcla_frame_pacing_mode was changed; FPS TARGET, FSR, HUD and frame guard preserved.'
