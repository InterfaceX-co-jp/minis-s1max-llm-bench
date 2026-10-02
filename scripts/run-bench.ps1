#Requires -Version 5.1
<#
.SYNOPSIS
  Benchmark Qwen3.8-Flash-Next GGUF with llama.cpp on Minisforum (unified memory).
.DESCRIPTION
  Runs llama-cli over a prompt-length matrix, parses llama.cpp's own timing lines
  (prompt eval tok/s = prefill, eval tok/s = decode) and writes a CSV.
.EXAMPLE
  .\run-bench.ps1 -Quant Q4_K_M -Contexts 1024,4096,8192
#>
param(
    [ValidateSet('Q2_K','Q3_K_M','Q4_K_M','Q5_K_M','Q6_K')]
    [string]$Quant = 'Q4_K_M',
    [string]$ModelDir = "$PSScriptRoot\..\models\qwen38-flash-next",
    [string]$LlamaCli = "$PSScriptRoot\..\bin\llama-cli.exe",
    # Prompt sizes (tokens) to prefill-benchmark. -p + -n generates text of that size.
    [int[]]$Contexts = 1024, 4096, 8192,
    # Decode tokens per run
    [int]$GenTokens = 256,
    [int]$Repeats = 3,
    [int]$Threads = 0,          # 0 = auto
    [switch]$NoMtp,             # skip MTP speculative decode
    [string]$CsvPath = ''
)

$ErrorActionPreference = 'Stop'

if (-not $CsvPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $CsvPath = Join-Path $PSScriptRoot "..\results\bench-$Quant-$stamp.csv"
}
New-Item -ItemType Directory -Force -Path (Split-Path $CsvPath) | Out-Null

# Locate model: shard 1 of the quant
$quantDir = Join-Path $ModelDir $Quant
$shard1 = Get-ChildItem -Path $quantDir -Filter '*00001-of-00007.gguf' | Select-Object -First 1
if (-not $shard1) { throw "Model shard not found in $quantDir. Run download-model.ps1 first." }

# Warm-up + RAM sanity
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("Free RAM: {0:N1} GB / {1:N1} GB" -f ($os.FreePhysicalMemory/1MB), ($os.TotalVisibleMemorySize/1MB))
if (($os.FreePhysicalMemory/1MB) -lt 100) { Write-Warning "Free RAM < 100 GB; PLE is mmap/NVMe-backed so it can still run, but expect slowness." }

$commonArgs = @(
    '-m', $shard1.FullName,
    '--load-mode', 'mmap',
    '-ngl', '99',
    '-ot', 'per_layer_token_embd.weight=CPU',
    '-st', '--temp', '0'
)
if ($Threads -gt 0) { $commonArgs += @('-t', "$Threads") }
if (-not $NoMtp) { $commonArgs += @('--spec-type', 'draft-mtp') }

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($ctx in $Contexts) {
    for ($r = 1; $r -le $Repeats; $r++) {
        Write-Host "`n=== ctx=$ctx gen=$GenTokens run=$r/$Repeats ===" -ForegroundColor Yellow
        $args2 = $commonArgs + @('-c', "$ctx", '-n', "$GenTokens", '-p', "Summarize the history of computing. " * 40)
        $out = & $LlamaCli @args2 2>&1 | Out-String
        $logFile = Join-Path (Split-Path $CsvPath) "log-$Quant-ctx$ctx-r$r.txt"
        Set-Content -Path $logFile -Value $out -Encoding UTF8

        # Parse llama.cpp timing lines, e.g.
        #   prompt eval time = ... / 1024 tokens ...  prompt eval speed =  1234.56 tokens/s
        #   eval time = ... / 256 runs ... eval speed =  45.67 tokens/s
        $prefill = if ($out -match 'prompt eval speed\s*=\s*([\d.]+)') { [double]$Matches[1] } else { 0 }
        $decode  = if ($out -match '(?<!prompt )eval speed\s*=\s*([\d.]+)') { [double]$Matches[1] } else { 0 }
        $peakRss = if ($out -match 'peak.*?MiB[^\d]*([\d.]+)') { [double]$Matches[1] } else { 0 }

        if ($decode -eq 0) { Write-Warning "No timing parsed; see $logFile" }
        $rows.Add([pscustomobject]@{
            timestamp = Get-Date -Format 'o'
            quant     = $Quant
            ctx       = $ctx
            run       = $r
            prefill_tps = $prefill
            decode_tps  = $decode
            peak_mem_mib = $peakRss
            mtp      = (-not $NoMtp)
        })
        Write-Host ("prefill {0:N1} tok/s | decode {1:N1} tok/s" -f $prefill, $decode) -ForegroundColor Green
    }
}

# Append (or create) CSV
$exists = Test-Path $CsvPath
$rows | Export-Csv -Path $CsvPath -NoTypeInformation -Append:(-not $exists)
Write-Host "`nSaved: $(Resolve-Path $CsvPath)" -ForegroundColor Cyan

# Summary (median decode by ctx)
$rows | Group-Object ctx | ForEach-Object {
    $d = $_.Group.decode_tps | Sort-Object
    $m = $d[[int][math]::Floor($d.Count/2)]
    [pscustomobject]@{ ctx=$_.Name; median_decode_tps=[math]::Round($m,2) }
} | Format-Table -AutoSize
