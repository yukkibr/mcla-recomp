# Visual-only traffic LOD A/B: leaves all traffic spawning, physics and timing untouched.
# Run when MCLA is closed. -Mode normal tests the game's 1.0 traffic LOD.
# -Mode restore sets the exact saved previous value (normally 0.5).
param([ValidateSet('normal','restore','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='mcla_traffic_lod'
$backup=Join-Path $root 'out\phase2-backup\pre-traffic-visual-lod-ab\mcla.toml'
if(-not (Test-Path -LiteralPath $config)){throw "Missing MCLA configuration: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close MCLA first to keep the A/B comparable.'
}
$lines=@([IO.File]::ReadAllLines($config))
function GetSetting($texts,$name){
    $hits=@($texts|Where-Object {($_ -split '=',2)[0].Trim() -eq $name})
    if($hits.Count){return ($hits[-1] -split '=',2)[1].Trim()}
    return $null
}
if($Mode -eq 'status'){
    foreach($name in @('mcla_traffic_lod','mcla_traffic_distance',
          'mcla_parked_cars','mcla_pedestrians','mcla_fps',
          'mcla_camera_smoothing_mode','mcla_frame_stall_guard_ms')){
        $value=GetSetting $lines $name
        if($null -ne $value){Write-Output "$name = $value"}
    }
    Write-Output "Original A/B backup: $(Test-Path -LiteralPath $backup)"
    return
}
if($Mode -eq 'normal'){
    if(-not (Test-Path -LiteralPath $backup)){
        New-Item -ItemType Directory -Force (Split-Path $backup -Parent) | Out-Null
        Copy-Item -LiteralPath $config -Destination $backup
    }
    $value='1.0'
}else{
    if(-not (Test-Path -LiteralPath $backup)){
        throw 'Original visual LOD backup absent; refusing to guess original value.'
    }
    $orig=@([IO.File]::ReadAllLines($backup))
    $value=GetSetting $orig $key
    if($null -eq $value){throw 'Original visual LOD key missing; refusing to guess.'}
}
$modified=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$modified += "$key = $value"
[IO.File]::WriteAllLines($config,[string[]]$modified,[Text.UTF8Encoding]::new($false))
Write-Output "Visual traffic LOD trial: $Mode; $key = $value. Reopen MCLA."
Write-Output 'Other options (traffic quantity/distance, physics, shadows, FPS and camera) untouched.'
