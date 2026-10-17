# Compare original ReXGlue texture request path against optional no-op/scratch reuse.
# Usage: .\scripts\texture_fastpath_trial.ps1 -Mode on|off|status [-Frametime keep|on|off]
# Frametime logging stays as-is unless explicitly changed.
param([ValidateSet('on', 'off', 'status')][string]$Mode = 'status',
      [ValidateSet('keep', 'on', 'off')][string]$Frametime = 'keep')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backupDir = Join-Path $root 'out\phase2-backup\pre-texture-request-fast-path'
$backup = Join-Path $backupDir 'mcla.toml'
if (-not (Test-Path -LiteralPath $config)) { throw "Missing config $config" }
if ($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw 'Close MCLA before changing the texture fast-path setting.'
}
$raw = [IO.File]::ReadAllText($config)
$key = 'texture_request_fast_path'
if ($Mode -eq 'status') {
    $hit = [regex]::Match($raw, '(?m)^[ \t]*' + $key + '[ \t]*=[ \t]*(true|false)')
    Write-Output ("texture_request_fast_path = " + $(if ($hit.Success) { $hit.Groups[1].Value } else { 'false (default)' }))
    $fpsHit = [regex]::Match($raw, '(?m)^[ \t]*mcla_fps_benchmark[ \t]*=[ \t]*(true|false)')
    Write-Output ("mcla_fps_benchmark = " + $(if ($fpsHit.Success) { $fpsHit.Groups[1].Value } else { 'false (default)' }))
    exit 0
}
New-Item -ItemType Directory -Force $backupDir | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
# Parse assignments line-by-line, removing ALL old/duplicate values even if
# an earlier helper left malformed trailing characters in a value.
$value = if ($Mode -eq 'on') { 'true' } else { 'false' }
$lines = @([IO.File]::ReadAllLines($config) | Where-Object {
    $name = ($_ -split '=', 2)[0].Trim()
    ($name -ne $key) -and ($Frametime -eq 'keep' -or $name -ne 'mcla_fps_benchmark')
})
$lines += "$key = $value"
if ($Frametime -ne 'keep') {
    $record = if ($Frametime -eq 'on') { 'true' } else { 'false' }
    $lines += "mcla_fps_benchmark = $record"
}
[IO.File]::WriteAllLines($config, $lines, (New-Object Text.UTF8Encoding($false)))
Write-Output "Texture request fast path $Mode. Original invalidation and uploads are preserved."
Write-Output 'Close and reopen MCLA to apply; keep all other graphics settings unchanged.'
