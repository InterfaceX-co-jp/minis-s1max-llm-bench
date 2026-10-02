#Requires -Version 5.1
<#
.SYNOPSIS
  Benchmark Qwen3.8-Flash-Next via a TensorFold server (OpenAI-compatible API).
.DESCRIPTION
  Starts `tensorfold serve` (or attaches to an already-running server), then measures:
    - prefill speed: long prompt, max_tokens=1, time / prompt tokens
    - decode speed:  streamed generation, tokens / elapsed seconds
  Run this on a machine where TensorFold runs (Apple Silicon MLX, or CUDA cc >= 8.9).
  NOTE: TensorFold does NOT run natively on Minisforum S1 Max (AMD Strix Halo) —
  use this on a Mac / NVIDIA box and compare against llama.cpp numbers from run-bench.ps1.
.EXAMPLE
  .\run-bench-tensorfold.ps1                                    # local server auto-start
  .\run-bench-tensorfold.ps1 -BaseUrl http://mac-mini.local:8080 -NoServe
#>
param(
    [string]$Checkpoint = 'TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP',
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [switch]$NoServe,               # attach to already-running server
    [int[]]$PromptTokens = 1024, 4096, 8192,
    [int]$GenTokens = 256,
    [int]$Repeats = 3,
    [string]$ExtraServeArgs = '',   # e.g. '--no-drafts' / '--mtp-drafts 4' / '--kv-dtype int8'
    [string]$CsvPath = ''
)
$ErrorActionPreference = 'Stop'

if (-not $CsvPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tag = ($Checkpoint -replace '[^A-Za-z0-9.-]', '_')
    $CsvPath = Join-Path $PSScriptRoot "..\results\tensorfold-$tag-$stamp.csv"
}
New-Item -ItemType Directory -Force -Path (Split-Path $CsvPath) | Out-Null

$serverProc = $null
if (-not $NoServe) {
    Write-Host "Starting tensorfold serve $Checkpoint $ExtraServeArgs" -ForegroundColor Cyan
    $serverProc = Start-Process -FilePath 'tensorfold' -ArgumentList "serve $Checkpoint $ExtraServeArgs" `
        -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path (Split-Path $CsvPath) 'tensorfold-serve.log') `
        -RedirectStandardError (Join-Path (Split-Path $CsvPath) 'tensorfold-serve.err.log')
    # Wait for /v1/models (up to 30 min: first run downloads ~25-30 GB)
    $deadline = (Get-Date).AddMinutes(30)
    do {
        Start-Sleep -Seconds 5
        try { $null = Invoke-RestMethod "$BaseUrl/v1/models" -TimeoutSec 5; $ok = $true } catch { $ok = $false }
        if ((Get-Date) -gt $deadline) { throw "Server did not come up in 30 min. Check tensorfold-serve.err.log" }
    } until ($ok)
    Write-Host "Server ready." -ForegroundColor Green
}

function Invoke-ChatStream {
    param([string]$Prompt, [int]$MaxTokens)
    # POST with stream=true; count chunks and measure wall time
    $body = @{
        model      = $Checkpoint
        messages   = @(@{ role = 'user'; content = $Prompt })
        max_tokens = $MaxTokens
        stream     = $true
        temperature = 0
    } | ConvertTo-Json -Depth 5
    $req = [System.Net.Http.HttpRequestMessage]::new('POST', "$BaseUrl/v1/chat/completions")
    $req.Content = [System.Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'application/json')
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromHours(2)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $stream = $resp.Content.ReadAsStream()
    $reader = [IO.StreamReader]::new($stream)
    $tokens = 0
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -like 'data: *' -and $line -ne 'data: [DONE]') { $tokens++ }
    }
    $sw.Stop()
    $reader.Dispose(); $stream.Dispose(); $resp.Dispose(); $req.Dispose()
    [pscustomobject]@{ tokens = $tokens; seconds = $sw.Elapsed.TotalSeconds }
}

# ~3.5 chars/token for English; used to size prompts roughly
$filler = ("The history of computing spans mechanical calculators, vacuum tubes, transistors, " +
           "integrated circuits, microprocessors and modern multi-core CPUs. " * 60)

$rows = [System.Collections.Generic.List[object]]::new()
try {
    # --- prefill benchmark: long prompt, max_tokens=1
    foreach ($pt in $PromptTokens) {
        for ($r = 1; $r -le $Repeats; $r++) {
            $n = [math]::Max(1, [int]($pt * 3.5 / $filler.Length))
            $prompt = $filler * $n
            Write-Host "prefill ~$pt tokens (run $r/$Repeats) ..." -ForegroundColor Yellow
            $m = Invoke-ChatStream -Prompt $prompt -MaxTokens 1
            # tokens are estimated from chars/3.5; seconds measured precisely
            $tps = ($prompt.Length / 3.5) / $m.seconds
            $rows.Add([pscustomobject]@{ timestamp=(Get-Date -Format 'o'); kind='prefill'; target_tokens=$pt; run=$r; tps=[math]::Round($tps,2); seconds=[math]::Round($m.seconds,3) })
            Write-Host ("  prefill ~{0:N0} tok/s" -f $tps) -ForegroundColor Green
        }
    }
    # --- decode benchmark: short prompt, stream GenTokens
    for ($r = 1; $r -le $Repeats; $r++) {
        Write-Host "decode $GenTokens tokens (run $r/$Repeats) ..." -ForegroundColor Yellow
        $m = Invoke-ChatStream -Prompt 'Write a detailed essay about the history of computing.' -MaxTokens $GenTokens
        $tps = $m.tokens / $m.seconds
        $rows.Add([pscustomobject]@{ timestamp=(Get-Date -Format 'o'); kind='decode'; target_tokens=$GenTokens; run=$r; tps=[math]::Round($tps,2); seconds=[math]::Round($m.seconds,3); actual_tokens=$m.tokens })
        Write-Host ("  decode {0:N1} tok/s ({1} tokens)" -f $tps, $m.tokens) -ForegroundColor Green
    }
}
finally {
    if ($serverProc -and -not $serverProc.HasExited) {
        Write-Host "Stopping tensorfold server (pid $($serverProc.Id))" -ForegroundColor DarkGray
        Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    }
}

$exists = Test-Path $CsvPath
$rows | Export-Csv -Path $CsvPath -NoTypeInformation -Append:(-not $exists)
Write-Host "`nSaved: $(Resolve-Path $CsvPath)" -ForegroundColor Cyan

$rows | Group-Object kind | ForEach-Object {
    $t = $_.Group.tps | Sort-Object
    [pscustomobject]@{ kind = $_.Name; median_tps = [math]::Round($t[[int][math]::Floor($t.Count/2)],2) }
} | Format-Table -AutoSize
