# Reversible controlled cache retention experiment. Does not rebuild the game.
# Usage: .\scripts\texture_cache_trial.ps1 -Mode retention
#        .\scripts\texture_cache_trial.ps1 -Mode original
#        .\scripts\texture_cache_trial.ps1 -Mode status
param([ValidateSet("original", "retention", "status")][string]$Mode = "status")

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$config = Join-Path $root "out\build\win-amd64-release\mcla.toml"
$backupDir = Join-Path $root "out\phase2-backup\texture-cache-retention"
$backup = Join-Path $backupDir "original-mcla.toml"

if (-not (Test-Path -LiteralPath $config)) {
    throw "Missing game mcla.toml: $config"
}
if ($Mode -ne "status" -and (Get-Process mcla -ErrorAction SilentlyContinue)) {
    throw "Close MCLA before changing texture-cache settings; they require a restart."
}

$values = @{
    "original" = @{
        texture_cache_memory_limit_soft = 384
        texture_cache_memory_limit_hard = 768
        texture_cache_memory_limit_soft_lifetime = 30
    }
    "retention" = @{
        texture_cache_memory_limit_soft = 768
        texture_cache_memory_limit_hard = 1024
        texture_cache_memory_limit_soft_lifetime = 90
    }
}
if ($Mode -eq "status") {
    $raw = Get-Content -LiteralPath $config -Raw
    foreach ($name in @("texture_cache_memory_limit_soft",
                        "texture_cache_memory_limit_hard",
                        "texture_cache_memory_limit_soft_lifetime")) {
        $found = [regex]::Match($raw, "(?m)^\s*" + $name + "\s*=\s*(\d+)")
        if ($found.Success) {
            Write-Output ("{0} = {1}" -f $name, $found.Groups[1].Value)
        } else {
            $default = @{ texture_cache_memory_limit_soft = 384; texture_cache_memory_limit_hard = 768; texture_cache_memory_limit_soft_lifetime = 30 }[$name]
            Write-Output ("{0} = SDK default ({1})" -f $name, $default)
        }
    }
    Write-Output ("Config: " + $config)
    exit 0
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $config -Destination $backup
}
$raw = [IO.File]::ReadAllText($config)
# Remove all existing copies of ONLY the three cache options. The original
# config may contain CRLF and repeated entries from prior tests; eliminating
# duplicates avoids relying on parser precedence between conflicting values.
$names = @("texture_cache_memory_limit_soft",
           "texture_cache_memory_limit_hard",
           "texture_cache_memory_limit_soft_lifetime")
$regex = "(?m)^[ \t]*(?:texture_cache_memory_limit_soft|texture_cache_memory_limit_hard|texture_cache_memory_limit_soft_lifetime)[ \t]*=[^\r\n]*(?:\r?\n|$)"
$raw = [regex]::Replace($raw, $regex, "")
$raw = $raw.TrimEnd([char[]]@([char]13, [char]10))
foreach ($name in $names) {
    $raw += "`r`n$name = $($values[$Mode][$name])"
}
$raw += "`r`n"
[IO.File]::WriteAllText($config, $raw, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("Texture cache trial mode: " + $Mode)
foreach ($name in @("texture_cache_memory_limit_soft",
                    "texture_cache_memory_limit_hard",
                    "texture_cache_memory_limit_soft_lifetime")) {
    Write-Output ("{0} = {1}" -f $name, $values[$Mode][$name])
}
Write-Output ("Original config backup: " + $backup)
Write-Output "All other game settings remain unchanged. Restart MCLA to apply."
