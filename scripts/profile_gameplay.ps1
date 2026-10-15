# Launch a normal gameplay session with ReXGlue per-frame and host CPU telemetry.
# Example: .\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4
# Does NOT forcefully close the game or modify game data.
param(
    [ValidateRange(30, 3600)][int]$CaptureSeconds = 300,
    [ValidateSet("current", "auto", "2", "4", "8")][string]$PipelineWorkers = "current",
    [switch]$GpuSamples,
    [string[]]$ExtraArgs = @()
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root "out\build\win-amd64-release"
if (Get-Process mcla -ErrorAction SilentlyContinue) {
    throw "Close any existing MCLA instance first to avoid overlapping sessions"
}
if (-not (Test-Path (Join-Path $build "mcla.exe"))) { throw "Build missing" }
if (-not (Test-Path (Join-Path $root "game\default.xex"))) { throw "Extracted game missing" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$folder = Join-Path $root "out\profiles\$stamp"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$frames = Join-Path $folder "frames.csv"
$sys = Join-Path $folder "host.csv"
$log = Join-Path $folder "game.log"
$argsList = @(
    "--game_data_root=$root\game",
    "--gpu_plugin=xenos",
    "--mcla_gpu_backend=d3d12",
    "--fullscreen=false",
    "--log_file=$log",
    "--log_level=info"
) + $ExtraArgs
if ($PipelineWorkers -ne "current") {
    $count = if ($PipelineWorkers -eq "auto") { "-1" } else { $PipelineWorkers }
    $argsList += "--d3d12_pipeline_creation_threads=$count"
}
$oldEnv = [Environment]::GetEnvironmentVariable("REX_PERF_LOG_CSV", "Process")
$gpuTool = if ($GpuSamples) { Get-Command nvidia-smi -ErrorAction SilentlyContinue } else { $null }
$env:REX_PERF_LOG_CSV = $frames
$process = $null
$gameStillRunning = $false
$samples = New-Object 'System.Collections.Generic.List[object]'
try {
    Write-Output "Launching the game with ReXGlue frame telemetry."
    Write-Output "Play normally in a dense city area. Do not run compilers or games in the background."
    Write-Output "Capture: $CaptureSeconds seconds, then the game will be left open if still running."
    Write-Output "Pipeline workers: $PipelineWorkers"
    Write-Output "Diagnostics folder: $folder"
    $process = Start-Process -FilePath (Join-Path $build "mcla.exe") -ArgumentList $argsList -WorkingDirectory $build -PassThru
    $started = Get-Date
    $oldTime = $started
    $oldCpu = 0.0
    $tick = 0
    while (((Get-Date) - $started).TotalSeconds -lt $CaptureSeconds) {
        Start-Sleep -Seconds 1
        $tick++
        $process.Refresh()
        if ($process.HasExited) {
            Write-Output "Game exited on its own with exit code $($process.ExitCode)"
            break
        }
        $now = Get-Date
        $delta = [math]::Max(.001, ($now - $oldTime).TotalSeconds)
        $cpu = $process.TotalProcessorTime.TotalSeconds
        $gpu = ""
        $vram = ""
        if ($gpuTool -and ($tick % 4 -eq 0)) {
            try {
                $line = & $gpuTool.Source "--query-gpu=utilization.gpu,memory.used" "--format=csv,noheader,nounits" 2>$null | Select-Object -First 1
                if ($line) {
                    $parts = $line -split ","
                    if ($parts.Count -ge 2) { $gpu = $parts[0].Trim(); $vram = $parts[1].Trim() }
                }
            } catch { }
        }
        $samples.Add([pscustomobject]@{
            elapsed_s = [math]::Round(($now - $started).TotalSeconds, 2)
            process_cpu_pct_one_core = [math]::Round(100 * ($cpu - $oldCpu) / $delta, 1)
            process_ram_mb = [math]::Round($process.WorkingSet64 / 1MB, 1)
            process_threads = $process.Threads.Count
            gpu_util_pct = $gpu
            gpu_vram_mb = $vram
        })
        $oldTime = $now
        $oldCpu = $cpu
        if ($tick % 30 -eq 0) { Write-Output "Captured $tick seconds..." }
    }
} finally {
    [Environment]::SetEnvironmentVariable("REX_PERF_LOG_CSV", $oldEnv, "Process")
    if ($samples.Count -gt 0) { $samples | Export-Csv -NoTypeInformation -Encoding UTF8 $sys }
    if ($process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            $gameStillRunning = $true
            Write-Output "Capture interval complete; game is STILL RUNNING. Save/quit when ready (Alt+F4 if QUIT GAME fails)."
        }
        $process.Dispose()
    }
}
if ($gameStillRunning) {
    # ReXGlue locks its per-frame CSV for the lifetime of the process on Windows.
    # Keep the game alive, and provide the exact report command for afterwards.
    Write-Output "Frame CSV is locked until the game exits. After quitting, run:"
    Write-Output ('python .\scripts\report_frame_spikes.py "{0}" --warmup 30 --slow-ms 50' -f $frames)
} elseif (Test-Path $frames) {
    & python (Join-Path $PSScriptRoot "report_frame_spikes.py") $frames --warmup 30 --slow-ms 50
    if ($LASTEXITCODE -ne 0) { Write-Warning "Frame report failed; original CSV and log are preserved" }
} else {
    Write-Warning "No ReXGlue frames were recorded; check game.log for startup errors"
}
Write-Output "Raw host telemetry: $sys"
Write-Output "Raw game log: $log"
Write-Output "Diagnostics folder: $folder"
