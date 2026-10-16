# Reversible CPU-side DX12 frame hitch and guest simulation timing probe.
# Usage: .\scripts\dx12_hitch_trial.ps1 -Mode on|off|status
param([ValidateSet("on", "off", "status")][string]$Mode = "status")
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backupDir = Join-Path $root 'out\phase2-backup\pre-dx12-hitch-probe'
$backup = Join-Path $backupDir 'mcla.toml'
if (-not (Test-Path -LiteralPath $config)) { throw "Missing game config: $config" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing the DX12 diagnostic configuration.'
}
$raw = [IO.File]::ReadAllText($config)
$keys = @('d3d12_hitch_probe', 'mcla_timing_trace', 'dx12_texture_stage_probe')
if ($Mode -eq 'status') {
    foreach ($key in $keys) {
        $m = [regex]::Match($raw, '(?m)^[ \t]*' + $key + '[ \t]*=[ \t]*(true|false)')
        $value = if ($m.Success) { $m.Groups[1].Value } else { 'false (default)' }
        Write-Output "$key = $value"
    }
    Write-Output ("Config: " + $config)
    exit 0
}
New-Item -ItemType Directory -Force $backupDir | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$enabled = if ($Mode -eq 'on') { 'true' } else { 'false' }
foreach ($key in $keys) {
    $raw = [regex]::Replace(
        $raw,
        '(?m)^[ \t]*' + $key + '[ \t]*=[^\r\n]*(?:\r?\n|$)',
        '')
}
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
foreach ($key in $keys) { $raw += "`r`n$key = $enabled" }
$raw += "`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object Text.UTF8Encoding($false)))
Write-Output "DX12 + guest timing hitch probes: $Mode ($enabled)"
Write-Output 'No rendering, game logic, resolution, scissor or texture budget settings changed.'
Write-Output 'Restart MCLA to apply. Disable after the short city test.'
