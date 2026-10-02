#Requires -Version 5.1
<#
.SYNOPSIS
  Run llama-bench (Vulkan) on the MS-S1 MAX: pp (prefill) + tg (decode) tok/s.
.DESCRIPTION
  Thin wrapper around llama-bench so results land in results\ as CSV and repeat cleanly.
  Default: -ngl 999 -p 512 -n 256 (pp512 / tg256 — the two numbers that matter).
  Use -PromptSizes / -GenSizes to sweep, -ExtraArgs to pass anything else
  (e.g. MTP/speculative flags of your build, -fa, --no-mmap).
.EXAMPLE
  .\run-bench-vulkan.ps1 -Model C:\models\model.gguf
  .\run-bench-vulkan.ps1 -Model C:\models\model.gguf -PromptSizes 512,4096 -GenSizes 256
  .\run-bench-vulkan.ps1 -Model . -ExtraArgs '--spec-type','draft-mtp'
#>
param(
    [string]$Model = '',
    [string]$LlamaBench = "$PSScriptRoot\..\bin\llama-bench.exe",
    [int[]]$PromptSizes = 512,
    [int[]]$GenSizes = 256,
    [int]$Repeats = 3,
    [int]$Ngl = 999,
    [string[]]$ExtraArgs = @(),
    [string]$CsvPath = ''
)
$ErrorActionPreference = 'Stop'

if (-not $Model) {
    # default: first shard of the downloaded quant, or any gguf in models\
    $cand = Get-ChildItem "$PSScriptRoot\..\models" -Recurse -Filter '*00001-of-*.gguf' | Select-Object -First 1
    if (-not $cand) { $cand = Get-ChildItem "$PSScriptRoot\..\models" -Recurse -Filter '*.gguf' | Select-Object -First 1 }
    if (-not $cand) { throw "No model found under models\. Pass -Model <path>." }
    $Model = $cand.FullName
    Write-Host "Auto-selected model: $Model"
}
if (-not (Test-Path $LlamaBench)) {
    $found = Get-ChildItem "$PSScriptRoot\..\bin" -Recurse -Filter 'llama-bench.exe' | Select-Object -First 1
    if (-not $found) { throw "llama-bench.exe not found. Run download-llamacpp.ps1 first." }
    $LlamaBench = $found.FullName
}
if (-not $CsvPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $CsvPath = Join-Path $PSScriptRoot "..\results\llamabench-$stamp.csv"
}
New-Item -ItemType Directory -Force -Path (Split-Path $CsvPath) | Out-Null

# Show devices once so the log proves the 8060S was used
$cli = Join-Path (Split-Path $LlamaBench) 'llama-cli.exe'
if (Test-Path $cli) {
    Write-Host '--- devices ---' -ForegroundColor DarkCyan
    & $cli --list-devices
}

$pArg = ($PromptSizes | ForEach-Object { $_ }) -join ','
$nArg = ($GenSizes | ForEach-Object { $_ }) -join ','

# -o csv is supported by recent llama-bench; fall back to markdown if the flag fails
$rawArgs = @('-m', $Model, '-ngl', "$Ngl", '-p', $pArg, '-n', $nArg, '-r', "$Repeats") + $ExtraArgs
Write-Host "llama-bench $($rawArgs -join ' ')" -ForegroundColor Cyan
$raw = & $LlamaBench @rawArgs + @('-o','csv') 2>&1 | Out-String
if ($raw -notmatch ',') {   # probably usage error about -o; retry without
    $raw = & $LlamaBench @rawArgs 2>&1 | Out-String
}
$logFile = Join-Path (Split-Path $CsvPath) ("llamabench-" + (Split-Path $CsvPath -Leaf) + ".log")
Set-Content -Path $logFile -Value $raw -Encoding UTF8

# Parse CSV lines (llama-bench csv: header + one row per test)
$lines = ($raw -split "`r?`n") | Where-Object { $_ -match ',' }
if ($lines.Count -ge 2) {
    $rows = $lines | ConvertFrom-Csv
    $rows | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "`nSaved: $(Resolve-Path $CsvPath)" -ForegroundColor Green
} else {
    # markdown fallback: dump raw to csv path for manual reading
    Set-Content -Path $CsvPath -Value $raw -Encoding UTF8
    Write-Host "Could not parse as CSV; raw output saved to: $CsvPath" -ForegroundColor Yellow
}
Write-Host "`n--- output ---"
$raw
