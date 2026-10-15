# Phase 1 reproducible Windows benchmark. Never modifies guest data.
# Example: .\scripts\benchmark_phase1.ps1 -Targets 30,60 -Seconds 80 -Label baseline
param(
    [int[]]$Targets = @(30, 60),
    [ValidateRange(20, 900)][int]$Seconds = 80,
    [ValidateRange(5, 120)][int]$TailSeconds = 20,
    [string]$Label = "baseline",
    [string]$Preset = "win-amd64-release",
    [ValidateSet("d3d12", "vulkan")][string]$Backend = "d3d12",
    [string[]]$ExtraArgs = @()
)
$ErrorActionPreference = "Stop"
if ($Seconds -le $TailSeconds + 5) { throw "Seconds must exceed TailSeconds by at least 6" }
if ($Targets.Count -eq 0) { throw "At least one FPS target is required" }
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root "out\build\$Preset"
$exe = Join-Path $build "mcla.exe"
$plugin = Join-Path $build "rexgpu-xenos.dll"
if (-not (Test-Path $exe) -or -not (Test-Path $plugin)) { throw "Build or GPU plugin missing. Run scripts\make_pc.ps1 first." }
if (-not (Test-Path (Join-Path $root "game\default.xex"))) { throw "Extracted game missing." }
$Label = $Label -replace '[^a-zA-Z0-9_-]', '-'
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$folder = Join-Path $root "out\benchmarks\$stamp-$Label"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$originalPerf = [Environment]::GetEnvironmentVariable("REX_PERF_LOG_CSV", "Process")
$nv = Get-Command nvidia-smi -ErrorAction SilentlyContinue
function Get-Sha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($path)
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion)
$metadata = [ordered]@{
    schema = 1
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    label = $Label
    targets = @($Targets)
    seconds = $Seconds
    tail_seconds = $TailSeconds
    backend = $Backend
    preset = $Preset
    extra_args = @($ExtraArgs)
    git_commit = ((& git -C $root rev-parse HEAD) | Out-String).Trim()
    git_branch = ((& git -C $root branch --show-current) | Out-String).Trim()
    executable_sha256 = Get-Sha256 $exe
    plugin_sha256 = Get-Sha256 $plugin
    os = (Get-CimInstance Win32_OperatingSystem).Caption
    processor = $cpu.Name
    logical_processors = $cpu.NumberOfLogicalProcessors
    gpu = @($gpu)
    nvidia_smi_available = [bool]$nv
    notes = "Automated title/menu run; city camera changes over time. Compare in-game driving separately."
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $folder "metadata.json")
Write-Output "Benchmark output: $folder"
Write-Output "Backend: $Backend; targets: $($Targets -join ','); seconds each: $Seconds"
try {
    foreach ($fps in $Targets) {
        if ($fps -lt 0 -or $fps -gt 240) { throw "Unsupported FPS target: $fps" }
        $prefix = "fps-$fps"
        $csv = Join-Path $folder "$prefix-frames.csv"
        $log = Join-Path $folder "$prefix-game.log"
        $samplesPath = Join-Path $folder "$prefix-system.csv"
        $args = @(
            "--game_data_root=$root\game",
            "--gpu_plugin=xenos",
            "--mcla_gpu_backend=$Backend",
            "--mcla_fps=$fps",
            "--mcla_intro=fast",
            "--fullscreen=false",
            "--log_file=$log",
            "--log_level=info"
        ) + $ExtraArgs
        $env:REX_PERF_LOG_CSV = $csv
        $process = $null
        $samples = New-Object 'System.Collections.Generic.List[object]'
        Write-Output "Starting target $fps FPS ..."
        try {
            $process = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $build -PassThru
            $start = Get-Date
            $previousTime = $start
            $previousCpu = 0.0
            while (((Get-Date) - $start).TotalSeconds -lt $Seconds) {
                Start-Sleep -Seconds 1
                $process.Refresh()
                if ($process.HasExited) {
                    Write-Warning "Target $fps exited early with code $($process.ExitCode)"
                    break
                }
                $now = Get-Date
                $elapsed = ($now - $start).TotalSeconds
                $deltaWall = [Math]::Max(0.001, ($now - $previousTime).TotalSeconds)
                $totalCpu = $process.TotalProcessorTime.TotalSeconds
                $cpuCorePct = [Math]::Round(100.0 * ($totalCpu - $previousCpu) / $deltaWall, 1)
                $previousCpu = $totalCpu
                $previousTime = $now
                $gpuPct = ""
                $gpuMemMb = ""
                if ($nv) {
                    try {
                        $line = & $nv.Source "--query-gpu=utilization.gpu,memory.used" "--format=csv,noheader,nounits" 2>$null | Select-Object -First 1
                        if ($line) {
                            $parts = $line -split ','
                            if ($parts.Count -ge 2) {
                                $gpuPct = $parts[0].Trim()
                                $gpuMemMb = $parts[1].Trim()
                            }
                        }
                    } catch { }
                }
                $samples.Add([pscustomobject]@{
                    elapsed_s = [Math]::Round($elapsed, 2)
                    cpu_one_core_pct = $cpuCorePct
                    process_memory_mb = [Math]::Round($process.WorkingSet64 / 1MB, 1)
                    gpu_util_pct = $gpuPct
                    gpu_memory_mb = $gpuMemMb
                })
                if (([int]$elapsed % 15) -eq 0) {
                    Write-Output ("  {0:N0}s / {1}s | process CPU {2:N1}% of one core | RAM {3:N0} MB | GPU {4}" -f $elapsed, $Seconds, $cpuCorePct, ($process.WorkingSet64/1MB), $gpuPct)
                }
            }
        } finally {
            if ($process) {
                $process.Refresh()
                if (-not $process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    try { $process.WaitForExit(5000) | Out-Null } catch { }
                }
                $process.Dispose()
            }
            if ($samples.Count) { $samples | Export-Csv -NoTypeInformation -Encoding UTF8 $samplesPath }
        }
        if (-not (Test-Path $csv)) {
            Write-Warning "No per-frame telemetry at $csv. Check $log and perf patch."
        } else {
            $length = (Get-Item $csv).Length
            Write-Output "  frame CSV: $length bytes"
        }
        Start-Sleep -Seconds 2
    }
} finally {
    [Environment]::SetEnvironmentVariable("REX_PERF_LOG_CSV", $originalPerf, "Process")
}
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source (Join-Path $PSScriptRoot "benchmark_report.py") $folder -TailSeconds $TailSeconds
    if ($LASTEXITCODE -ne 0) { throw "Benchmark report generation failed" }
}
Write-Output "Completed: $folder"
