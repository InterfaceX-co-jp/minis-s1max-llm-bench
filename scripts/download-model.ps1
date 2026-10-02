#Requires -Version 5.1
<#
.SYNOPSIS
  Download Qwen3.8-Flash-Next GGUF (selected quant + shared PLE) from Hugging Face.
.EXAMPLE
  .\download-model.ps1 -Quant Q4_K_M -OutDir D:\models\qwen38-flash-next
#>
param(
    [ValidateSet('Q2_K','Q3_K_M','Q4_K_M','Q5_K_M','Q6_K')]
    [string]$Quant = 'Q4_K_M',
    [string]$OutDir = "$PSScriptRoot\..\models\qwen38-flash-next",
    [int]$Shards = 7,
    [switch]$SkipPle,
    # Unsloth UD-Q4_K_XL + shared MTP head — the checkpoint gufo / strixllama use.
    [switch]$Unsloth
)

$ErrorActionPreference = 'Stop'
$repo = 'vcruz305/Qwen3.8-Flash-Next-GGUF'
$base = "https://huggingface.co/$repo/resolve/main"

# Resolve OutDir relative to repo root (script lives in scripts\)
if ($OutDir -match '^\.\.') {
    $OutDir = Join-Path (Join-Path $PSScriptRoot '..') $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$quantDir = Join-Path $OutDir $Quant
New-Item -ItemType Directory -Force -Path $quantDir | Out-Null

function Get-File {
    param([string]$Url, [string]$Dest)
    $name = Split-Path $Dest -Leaf
    if (Test-Path $Dest) {
        Write-Host "SKIP (exists): $name" -ForegroundColor DarkGray
        return
    }
    Write-Host "GET $name ..." -ForegroundColor Cyan
    # curl.exe is fast & resilient; available on Win10/11 and pwsh
    & curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o $Dest $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
}

if ($Unsloth) {
    # Unsloth UD-Q4_K_XL (single-file, sharded) + shared MTP head (Q8_0).
    # Used by gufo / strixllama on Strix Halo. See README "gufo" section.
    $repo2 = 'unsloth/Qwen3.8-Flash-Next-GGUF'
    $rev   = '38bb39ee97821de2c9009abb7e93950eec396e66'
    $base2 = "https://huggingface.co/$repo2/resolve/$rev"
    $udDir = Join-Path $OutDir 'UD-Q4_K_XL'
    New-Item -ItemType Directory -Force -Path $udDir | Out-Null
    # UD-Q4_K_XL is sharded as ...-00001-of-00003.gguf (adjust count if the repo changes)
    for ($i = 1; $i -le 3; $i++) {
        $n = '{0:D5}' -f $i
        Get-File "$base2/UD-Q4_K_XL/UD-Q4_K_XL-$n-of-00003.gguf" (Join-Path $udDir "UD-Q4_K_XL-$n-of-00003.gguf")
    }
    $mtpDir = Join-Path $OutDir 'MTP'
    New-Item -ItemType Directory -Force -Path $mtpDir | Out-Null
    Get-File "$base2/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf" (Join-Path $mtpDir 'mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf')
    Write-Host "Done. Unsloth UD-Q4_K_XL + MTP head in $udDir / $mtpDir" -ForegroundColor Green
    return
}

# Backbone shards 00001..00006, PLE acts as shard 00007
for ($i = 1; $i -le $Shards - 1; $i++) {
    $n = '{0:D5}' -f $i
    $url  = "$base/$Quant/Qwen3.8-Flash-Next-$Quant-$n-of-00007.gguf"
    $dest = Join-Path $quantDir ("Qwen3.8-Flash-Next-$Quant-$n-of-00007.gguf")
    Get-File $url $dest
}

# Shared PLE (BF16, ~95.4 GiB) — used as shard 7 for every quant
$pleDest = Join-Path $OutDir 'PLE-BF16\Qwen3.8-Flash-Next-PLE-BF16.gguf'
if (-not $SkipPle) {
    New-Item -ItemType Directory -Force -Path (Split-Path $pleDest) | Out-Null
    Get-File "$base/PLE-BF16/Qwen3.8-Flash-Next-PLE-BF16.gguf" $pleDest

    # Hardlink (fallback: copy) PLE as shard 00007 of this quant
    $shard7 = Join-Path $quantDir "Qwen3.8-Flash-Next-$Quant-00007-of-00007.gguf"
    if (-not (Test-Path $shard7)) {
        try { New-Item -ItemType HardLink -Path $shard7 -Target $pleDest | Out-Null }
        catch { Copy-Item $pleDest $shard7 }
    }
    Write-Host "Linked PLE -> $shard7"
}

Write-Host "`nDone. Model dir: $quantDir" -ForegroundColor Green
