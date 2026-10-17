# Reversible A/B of 67ms Gentle guard vs 125ms Original guard.
# Execute with game closed: .\scripts\frame_guard_ab_trial.ps1 -Mode 67|125|status
param([ValidateSet('67','125','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$cfg=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backup=Join-Path $root 'out\phase2-backup\pre-guest-step-clamp-accounting\mcla.toml'
if (-not (Test-Path -LiteralPath $cfg)) { throw "Missing configuration $cfg" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing the guest time step.'
}
$rows=@([IO.File]::ReadAllLines($cfg))
$key='mcla_frame_stall_guard_ms'
if ($Mode -eq 'status') {
    $found=@($rows | Where-Object { ($_ -split '=',2)[0].Trim() -eq $key })
    if ($found.Count) { $found[-1] } else { "$key = 125 (default)" }
    Write-Output '67 = Gentle (shorter simulation steps); 125 = Original (longer catch-up steps).'
    Write-Output "Config: $cfg"
    return
}
New-Item -Force -ItemType Directory (Split-Path $backup -Parent) | Out-Null
if (-not (Test-Path -LiteralPath $backup)) { Copy-Item $cfg $backup }
$new=@($rows | Where-Object { ($_ -split '=',2)[0].Trim() -ne $key })
$new+="$key = $Mode"
[IO.File]::WriteAllLines($cfg,[string[]]$new,(New-Object Text.UTF8Encoding($false)))
Write-Output "Frame stall guard: $Mode ms. Applies on next game launch."
Write-Output 'This changes the maximum simulated time step after a hitch, NOT the rendered FPS.'
Write-Output 'Compare same route and physics/camera; restore -Mode 67 if motion gets worse.'
