# Automated test for the normal window close lifecycle, no in-game inputs.
param([int]$WarmupSeconds = 12, [int]$TimeoutSeconds = 25, [string[]]$ExtraArgs = @())
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'out\build\win-amd64-release'
$log = Join-Path $root ('out\runs\quit-qa-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
New-Item -Force -ItemType Directory (Join-Path $root 'out\runs') | Out-Null
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class QuitQA {
 [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
}
"@
$argsList = @(
 "--game_data_root=$root\game", '--gpu_plugin=xenos',
 '--mcla_gpu_backend=d3d12', '--fullscreen=false',
 '--mcla_intro=fast', '--mcla_fps=30',
 "--log_file=$log", '--log_level=info'
) + $ExtraArgs
$p = Start-Process -FilePath (Join-Path $build 'mcla.exe') -ArgumentList $argsList -WorkingDirectory $build -PassThru
try {
 Start-Sleep -Seconds $WarmupSeconds
 $p.Refresh()
 if ($p.HasExited) { throw "Exited before close (code $($p.ExitCode))" }
 if ($p.MainWindowHandle -eq [IntPtr]::Zero) { throw "No visible game window" }
 Write-Output "Posting WM_CLOSE to $($p.Id), HWND $($p.MainWindowHandle)"
 if (-not [QuitQA]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) { throw 'PostMessage failed' }
 $closed = $p.WaitForExit($TimeoutSeconds * 1000)
 $p.Refresh()
 Write-Output ("CLOSED={0} EXIT={1} LOG={2}" -f $closed, $(if ($closed) { $p.ExitCode } else { 'timeout' }), $log)
 if (-not $closed) { throw 'Normal WM_CLOSE did not terminate the process' }
} finally {
 $p.Refresh()
 if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
 $p.Dispose()
}
