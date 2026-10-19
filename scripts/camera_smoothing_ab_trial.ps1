# Reversible camera-only smoothing A/B. Requires game closed.
# Usage: .\scripts\camera_smoothing_ab_trial.ps1 -Mode per_frame|time_corrected|status
param([ValidateSet('per_frame','time_corrected','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='mcla_camera_smoothing_mode'
if(-not (Test-Path -LiteralPath $config)){throw "Missing config: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close MCLA before changing the camera-only A/B mode.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
    $found=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($found.Count){$found[-1]}else{"$key = time_corrected (default)"}
    $fps=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq 'mcla_fps'})
    if($fps.Count){$fps[-1]}
    Write-Output 'Only the chase camera position/look-at smoothing differs. Engine timer and FPS unchanged.'
    return
}
$backup=Join-Path $root 'out\phase2-backup\pre-camera-30hz-filter-ab\mcla.toml'
if(-not (Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
    Copy-Item -LiteralPath $config -Destination $backup
}
$filtered=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$filtered += ($key+' = '+[char]34+$Mode+[char]34)
[IO.File]::WriteAllLines($config,[string[]]$filtered,
                        (New-Object Text.UTF8Encoding($false)))
Write-Output "Chase camera smoothing A/B: $Mode (active next launch)"
Write-Output 'No FPS cap, physics changes, ReXGlue swap, FSR or texture config changes.'
