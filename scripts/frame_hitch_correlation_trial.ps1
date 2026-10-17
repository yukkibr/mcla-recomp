# Read-only frame-hitch, guest-delta and camera-motion correlation.
# Usage: .\scripts\frame_hitch_correlation_trial.ps1 -Mode on|off|status
param([ValidateSet('on','off','status')][string]$Mode = 'status')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backup = Join-Path $root 'out\phase2-backup\before-frame-hitch-correlation\mcla.toml'
if (-not (Test-Path -LiteralPath $config)) { throw "Missing configuration: $config" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing the hitch correlation setting.'
}
$lines = @([IO.File]::ReadAllLines($config))
$key = 'mcla_hitch_correlation'
if ($Mode -eq 'status') {
    $match = @($lines | Where-Object { $_ -match '^\s*mcla_hitch_correlation\s*=' })
    if ($match.Count -gt 0) {
        Write-Output ($match[-1].Trim())
    } else {
        Write-Output 'mcla_hitch_correlation = false (default)'
    }
    Write-Output "Config: $config"
    return
}
$dir = Split-Path $backup -Parent
New-Item -ItemType Directory -Force $dir | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$filtered = @($lines | Where-Object { ($_ -split '=',2)[0].Trim() -ne $key })
$value = if ($Mode -eq 'on') { 'true' } else { 'false' }
$filtered += "$key = $value"
[IO.File]::WriteAllLines($config, [string[]]$filtered, (New-Object Text.UTF8Encoding($false)))
Write-Output "Hitch correlation $Mode. No graphics, physics, FPS or texture settings changed."
Write-Output 'Restart MCLA to apply. Disable after recording a real drive.'
