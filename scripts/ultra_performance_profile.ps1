# Ultra Performance preset for MCLA ReXGlue — Windows DX12.
# Saves the FULL player mcla.toml and permits exact rollback.
# Usage:
#   .\scripts\ultra_performance_profile.ps1 -Mode on
#   .\scripts\ultra_performance_profile.ps1 -Mode status
#   .\scripts\ultra_performance_profile.ps1 -Mode restore
[CmdletBinding()]
param([ValidateSet('on','restore','status')][string]$Mode='status')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'out\build\win-amd64-release\mcla.toml'
$backup=Join-Path $root 'out\phase2-backup\pre-ultra-performance-profile\mcla.toml'
if(!(Test-Path -LiteralPath $config)){throw "MCLA config not found: $config"}
if($Mode -eq 'status'){
  $configured=[IO.File]::ReadAllLines($config)
  Write-Output ('Backup available: '+(Test-Path -LiteralPath $backup))
  foreach($key in @('mcla_gpu_backend','mcla_fps','vsync','mcla_render_quality',
        'mcla_city_profile','mcla_pedestrians','mcla_parked_cars','mcla_msaa',
        'mcla_motion_blur','mcla_shadows','mcla_race_shadows',
        'mcla_fast_guest_cache_flush','mcla_texture_cache_budget_mb',
        'mcla_single_tile','mcla_fence_yield','d3d12_scissor_cache',
        'texture_request_fast_path','mcla_fps_benchmark')) {
    $found=@($configured|Where-Object {($_ -split '=',2)[0].Trim() -eq $key})
    if($found.Count){Write-Output $found[-1]}else{Write-Output "$key = <built-in default>"}
  }
  return
}
if(Get-Process mcla -ErrorAction SilentlyContinue) {
  throw 'Close MCLA before changing its performance profile.'
}
if($Mode -eq 'restore'){
  if(!(Test-Path -LiteralPath $backup)){throw 'No original backup found. Refusing to guess your previous settings.'}
  Copy-Item -LiteralPath $backup -Destination $config -Force
  Write-Output 'Previous mcla.toml restored exactly, including personal preferences.'
  Write-Output "Original backup retained at $backup"
  return
}
New-Item -ItemType Directory -Force (Split-Path $backup -Parent)|Out-Null
if(!(Test-Path -LiteralPath $backup)){
  Copy-Item -LiteralPath $config -Destination $backup -ErrorAction Stop
  Write-Output "Original preference backup: $backup"
}else{
  Write-Output "Original preference backup retained: $backup"
}
$changes=[ordered]@{
  # Keep a real unlocked performance baseline on the proven backend.
  mcla_gpu_backend='"d3d12"'
  mcla_fps='0'
  vsync='false'
  mcla_frame_pacing_mode='"off"'
  mcla_frame_stall_guard_ms='67'
  mcla_camera_smoothing_mode='"time_corrected"'
  mcla_show_fps='true'
  mcla_fps_benchmark='true'
  # Lowest internal guest render size, scaled by existing FSR 1 presenter.
  mcla_render_quality='"performance"'
  resolution_scale='1'
  draw_resolution_scale_x='1'
  draw_resolution_scale_y='1'
  present_effect='"fsr"'
  # Minimum city preset: do not modify ambient moving traffic removal beyond 250m.
  mcla_city_profile='"minimum"'
  mcla_city_lod='0.5'
  mcla_traffic_lod='0.5'
  mcla_traffic_distance='250'
  mcla_pedestrians='0'
  mcla_parked_cars='0'
  mcla_shadows='false'
  mcla_race_shadows='false'
  mcla_fast_car_shadows='false'
  mcla_foliage_shadows='false'
  mcla_foliage_impostors='true'
  mcla_fullscreen_blur='false'
  mcla_msaa='false'
  mcla_motion_blur='false'
  mcla_depth_of_field='false'
  # Validated CPU-oriented renderer paths, optional flush fence experimental.
  mcla_single_tile='true'
  mcla_fence_yield='true'
  mcla_fast_guest_cache_flush='true'
  d3d12_scissor_cache='true'
  d3d12_scissor_cache_audit='false'
  d3d12_pipeline_creation_threads='8'
  d3d12_submit_on_primary_buffer_end='true'
  texture_request_fast_path='true'
  d3d12_texture_resource_pool_mb='128'
  # Safe budget is bounded by DXGI at boot, not the physical 8 GiB.
  mcla_texture_cache_budget_mb='-2'
  texture_cache_memory_limit_soft_lifetime='90'
  # Disable traces; rejected no-gain experiments aren't FPS optimizations.
  mcla_cache_flush_stats='false'
  d3d12_hitch_probe='false'
  dx12_texture_stage_probe='false'
  texture_request_sample_probe='false'
  texture_precheck_unscaled_cache='false'
  texture_cache_map_reserve='0'
  texture_cache_map_probe='false'
  mcla_hitch_correlation='false'
  mcla_sim_present_sync_probe='false'
  mcla_timing_trace='false'
  mcla_ab_test='""'
}
$before=@([IO.File]::ReadAllLines($config))
$present=@{}
foreach($line in $before){
 if($line -match '^\s*([A-Za-z0-9_]+)\s*='){
   $key=$Matches[1]
   if($changes.Contains($key)){
      if($present.ContainsKey($key)){throw "Duplicate config key: $key"}
      $present[$key]=$true
   }
 }
}
$after=@()
foreach($line in $before){
  if($line -match '^(\s*)([A-Za-z0-9_]+)(\s*=\s*)(.*)$'){
    $key=$Matches[2]
    if($changes.Contains($key)){
      $after+=("$($Matches[1])$key$($Matches[3])$($changes[$key])")
      continue
    }
  }
  $after+=$line
}
foreach($key in $changes.Keys){
  if(!$present.ContainsKey($key)){$after+=("$key = "+$changes[$key])}
}
$temp="$config.ultra.tmp"
try{
  [IO.File]::WriteAllLines($temp,[string[]]$after,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $config -Force
}catch{
  Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  throw
}
Write-Output 'ULTRA PERFORMANCE profile ACTIVATED.'
Write-Output "Changed/forced settings: $($changes.Count)."
Write-Output 'GPU: DirectX 12, FPS uncapped, 480p guest render + FSR, VSync OFF.'
Write-Output 'CPU: flush fence ON (experimental), single tile, scissor cache, fast textures.'
Write-Output 'Visuals: city MINIMUM, no pedestrians or parked cars, MSAA/shadows/blur OFF.'
Write-Output 'VRAM: MAX SAFE texture cache, DXGI-capped; this does not preallocate VRAM.'
Write-Output 'To restore everything exactly: .\scripts\ultra_performance_profile.ps1 -Mode restore'
