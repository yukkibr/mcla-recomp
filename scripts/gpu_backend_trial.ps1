# Launch MCLA for GPU backend A/B/A without editing the saved game configuration.
# Examples:
#   .\scripts\gpu_backend_trial.ps1 -Backend vulkan
#   .\scripts\gpu_backend_trial.ps1 -Backend d3d12
# Close the game normally between trials. Existing FPS, FSR and traffic settings remain.
param(
  [ValidateSet('d3d12','vulkan')][string]$Backend='d3d12',
  [switch]$WaitForExit,
  [switch]$NoAsyncShaderCompilation
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'out\build\win-amd64-release'
$game=Join-Path $root 'game'
$exe=Join-Path $build 'mcla.exe'
if(!(Test-Path -LiteralPath $exe)){throw "Missing build: $exe"}
if(!(Test-Path -LiteralPath (Join-Path $game 'default.xex'))){throw 'Game files missing'}
if(Get-Process mcla -ErrorAction SilentlyContinue){
  throw 'MCLA is already running. Close it normally before switching backends.'
}
$folder=Join-Path $root 'out\backend-trials'
New-Item -ItemType Directory -Force $folder|Out-Null
$time=Get-Date -Format 'yyyyMMdd-HHmmss'
$log=Join-Path $folder ("mcla-"+$Backend+"-"+$time+".log")
$settings=Join-Path $build 'mcla.toml'
$keys=@('mcla_fps','mcla_camera_smoothing_mode','present_effect',
        'mcla_traffic_lod','mcla_traffic_distance','vsync','draw_resolution_scale_x',
        'draw_resolution_scale_y','async_shader_compilation')
Write-Output "MCLA graphics backend: $Backend"
Write-Output 'Only the per-process backend is overridden; mcla.toml is not changed.'
Write-Output "Log: $log"
if(Test-Path -LiteralPath $settings){
  foreach($key in $keys){
    $found=@(Select-String -LiteralPath $settings -Pattern ('^\s*'+[regex]::Escape($key)+'\s*='))
    if($found.Count){Write-Output ($found[-1].Line.Trim())}
  }
}
$arguments=@(
    "--game_data_root=$game", '--gpu_plugin=xenos',
    "--mcla_gpu_backend=$Backend",
    "--log_file=$log", '--log_level=info'
)
if($NoAsyncShaderCompilation){
    $arguments+='--async_shader_compilation=false'
    Write-Output 'Caution: synchronous shader compilation can produce larger initial stutters.'
}
if($Backend -eq 'vulkan' -and !$NoAsyncShaderCompilation){
    Write-Output 'Vulkan skips presenting incomplete shader frames while warming shaders.'
    Write-Output 'Warm the city for 1-2 min and compare VISUAL motion; guest FPS is not hardware-present FPS.'
}
$proc=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $build -PassThru
Write-Output "Started MCLA PID=$($proc.Id)"
Write-Output 'Drive the same route/car/camera, then quit normally; never compare title-screen FPS.'
if($WaitForExit){
  try{
    $proc.WaitForExit()
    Write-Output "Game exited: code=$($proc.ExitCode)"
  }finally{$proc.Dispose()}
}else{
  $proc.Dispose()
}
Write-Output "Log path: $log"
