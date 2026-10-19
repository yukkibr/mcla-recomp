# Read-only guest timer/fixed-step versus present-request sequence diagnosis.
# Usage: .\scripts\sim_present_sync_trial.ps1 -Mode on|off|status
param([ValidateSet('on','off','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$key='mcla_sim_present_sync_probe'
if(!(Test-Path -LiteralPath $config)){throw "No config: $config"}
if($Mode -ne 'status' -and (Get-Process mcla -ErrorAction SilentlyContinue)){
    throw 'Close the game before modifying sim/present trace.'
}
$lines=@([IO.File]::ReadAllLines($config))
if($Mode -eq 'status'){
    $v=@($lines | Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($v.Count){$v[-1]}else{"$key = false (default)"}
    foreach($other in @('mcla_fps','mcla_camera_smoothing_mode','mcla_frame_stall_guard_ms')){
        $v=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -eq $other})
        if($v.Count){$v[-1]}
    }
    return
}
$backup=Join-Path $root 'out\phase2-backup\pre-sim-present-sync\mcla.toml'
if(!(Test-Path -LiteralPath $backup)){
    New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null
    Copy-Item -LiteralPath $config $backup
}
$lines=@($lines|Where-Object {($_ -split '=',2)[0].Trim() -ne $key})
$val=if($Mode -eq 'on'){'true'}else{'false'}
$lines += "$key = $val"
[IO.File]::WriteAllLines($config,[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Output "Read-only simulation timer/present sequence trace: $Mode"
Write-Output 'Only the trace toggled. No physics, camera, FPS, render timing or clamping changes.'
